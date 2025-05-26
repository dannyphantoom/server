import os
import stat
import time
import sqlite3
import threading
import queue
import tkinter as tk
from tkinter import ttk, messagebox

FIFO_PATH = "/tmp/assembly_chat_fifo"
DATABASE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "chat_history.db")


class ChatDatabase:
    """Simple wrapper around SQLite for storing chat messages."""

    def __init__(self, path: str = DATABASE_PATH):
        self.conn = sqlite3.connect(path)
        self._init_db()

    def _init_db(self) -> None:
        with self.conn:
            self.conn.execute(
                """
                CREATE TABLE IF NOT EXISTS messages (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp TEXT NOT NULL,
                    source TEXT DEFAULT 'Server',
                    content TEXT NOT NULL
                )
                """
            )

    def add_message(self, timestamp: str, message: str) -> None:
        with self.conn:
            self.conn.execute(
                "INSERT INTO messages(timestamp, source, content) VALUES(?, ?, ?)",
                (timestamp, "Server", message),
            )

    def get_all_messages(self):
        cur = self.conn.cursor()
        cur.execute(
            "SELECT timestamp, source, content FROM messages ORDER BY id ASC"
        )
        return cur.fetchall()

    def clear(self):
        with self.conn:
            self.conn.execute("DELETE FROM messages")


class ChatApp(tk.Tk):
    """Tkinter based GUI that receives messages from a FIFO."""

    def __init__(self) -> None:
        super().__init__()
        self.title("Assembly Chat Receiver")
        self.geometry("500x600")

        self.db = ChatDatabase()
        self.queue: queue.Queue = queue.Queue()
        self.running = True

        self._create_widgets()
        self._load_history()

        self.reader_thread = threading.Thread(target=self._fifo_reader, daemon=True)
        self.reader_thread.start()
        self.after(100, self._process_queue)

    # ------------------------------------------------------------------
    # GUI setup
    # ------------------------------------------------------------------
    def _create_widgets(self) -> None:
        # Menu
        menubar = tk.Menu(self)
        chat_menu = tk.Menu(menubar, tearoff=0)
        chat_menu.add_command(label="Clear Chat", command=self._clear_chat)
        menubar.add_cascade(label="Chat", menu=chat_menu)
        self.config(menu=menubar)

        # Chat display with scrollbar
        self.text = tk.Text(self, wrap=tk.WORD, state=tk.DISABLED)
        scrollbar = ttk.Scrollbar(self, command=self.text.yview)
        self.text.configure(yscrollcommand=scrollbar.set)
        self.text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.text.bind("<Button-3>", self._copy_selection)

        # Status bar
        self.status_var = tk.StringVar(value="Starting...")
        status = ttk.Label(self, textvariable=self.status_var, anchor="w")
        status.pack(side=tk.BOTTOM, fill=tk.X)

        self.protocol("WM_DELETE_WINDOW", self._on_close)

    # ------------------------------------------------------------------
    # Message handling
    # ------------------------------------------------------------------
    def _append_message(self, timestamp: str, message: str) -> None:
        """Append a message to the text widget."""
        self.text.configure(state=tk.NORMAL)
        at_bottom = self.text.yview()[1] >= 0.99
        self.text.insert(tk.END, f"[{timestamp}] Server says: {message}\n")
        if at_bottom:
            self.text.see(tk.END)
        self.text.configure(state=tk.DISABLED)

    def _load_history(self) -> None:
        for ts, src, msg in self.db.get_all_messages():
            self._append_message(ts, msg)

    def _clear_chat(self) -> None:
        if messagebox.askyesno("Clear Chat", "Delete all chat history?"):
            self.text.configure(state=tk.NORMAL)
            self.text.delete("1.0", tk.END)
            self.text.configure(state=tk.DISABLED)
            self.db.clear()

    # ------------------------------------------------------------------
    # FIFO reading thread
    # ------------------------------------------------------------------
    def _fifo_reader(self) -> None:
        while self.running:
            if not os.path.exists(FIFO_PATH):
                try:
                    os.mkfifo(FIFO_PATH)
                    self.queue.put(("STATUS", f"Named pipe {FIFO_PATH} created"))
                except OSError as e:
                    self.queue.put(("STATUS", f"Error creating FIFO: {e}"))
                    time.sleep(1)
                    continue
            else:
                if not stat.S_ISFIFO(os.stat(FIFO_PATH).st_mode):
                    self.queue.put(("STATUS", f"{FIFO_PATH} exists but is not a FIFO"))
                    time.sleep(5)
                    continue

            self.queue.put(("STATUS", "Waiting for server..."))
            try:
                with open(FIFO_PATH, "r") as fifo:
                    self.queue.put(("STATUS", "Connected"))
                    while self.running:
                        line = fifo.readline()
                        if line == "":
                            self.queue.put(("STATUS", "Server disconnected, reconnecting..."))
                            break
                        line = line.strip()
                        if line:
                            ts = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())
                            self.queue.put(("MESSAGE", (ts, line)))
            except Exception as e:  # noqa: BLE001
                self.queue.put(("STATUS", f"Error: {e}"))
                time.sleep(1)

    # ------------------------------------------------------------------
    # Queue processing and GUI callbacks
    # ------------------------------------------------------------------
    def _process_queue(self) -> None:
        try:
            while True:
                typ, payload = self.queue.get_nowait()
                if typ == "MESSAGE":
                    ts, msg = payload
                    self._append_message(ts, msg)
                    self.db.add_message(ts, msg)
                elif typ == "STATUS":
                    self.status_var.set(payload)
                self.queue.task_done()
        except queue.Empty:
            pass
        if self.running:
            self.after(100, self._process_queue)

    def _copy_selection(self, event=None) -> None:  # noqa: D401
        """Copy selected text to clipboard."""
        try:
            selection = self.text.get(tk.SEL_FIRST, tk.SEL_LAST)
            self.clipboard_clear()
            self.clipboard_append(selection)
        except tk.TclError:
            pass

    def _on_close(self) -> None:
        self.running = False
        self.status_var.set("Closing...")
        self.after(200, self.destroy)


def init_db():
    """Initializes the database and creates the messages table if it doesn't exist."""
    db_dir = os.path.dirname(DATABASE_PATH)
    if not os.path.exists(db_dir):
        try:
            os.makedirs(db_dir)
            print(f"Created directory for database: {db_dir}")
        except OSError as e:
            print(f"Error creating directory {db_dir}: {e}")
            raise
    conn = sqlite3.connect(DATABASE_PATH)
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            source TEXT DEFAULT 'Server',
            content TEXT NOT NULL
        )
    ''')
    conn.commit()
    print(f"Database initialized/table ensured at {DATABASE_PATH}")
    return conn

def add_message_to_db(conn, timestamp, message_content, source='Server'):
    """Adds a new message to the database."""
    if conn is None:
        print("Database connection is None. Cannot add message.")
        return
    cursor = conn.cursor()
    try:
        cursor.execute('''
            INSERT INTO messages (timestamp, source, content)
            VALUES (?, ?, ?)
        ''', (timestamp, source, message_content))
        conn.commit()
    except sqlite3.Error as e:
        print(f"Database Error (add_message_to_db): {e}")

def load_messages_from_db(conn, search_term=None, limit=None, offset=0):
    """Loads messages from the database. 
       Can filter by a search term (case-insensitive).
       Can limit results and provide an offset for pagination.
       Returns a list of dictionaries (for easier GUI use) or empty list on error.
    """
    if conn is None:
        print("Database connection is None. Cannot load messages.")
        return []
        
    cursor = conn.cursor()
    query = "SELECT id, timestamp, source, content FROM messages"
    params = []

    if search_term:
        query += " WHERE content LIKE ? ESCAPE '\\'" # Added ESCAPE for literal % and _ in search
        # Sanitize search_term for LIKE: escape % and _
        sanitized_search_term = search_term.replace('%', '\\%').replace('_', '\\_')
        params.append(f"%{sanitized_search_term}%")
    
    query += " ORDER BY timestamp ASC" # Always sort by timestamp

    if limit is not None:
        query += " LIMIT ?"
        params.append(limit)
        if offset > 0:
            query += " OFFSET ?"
            params.append(offset)

    try:
        cursor.execute(query, params)
        messages = [
            dict(zip([column[0] for column in cursor.description], row))
            for row in cursor.fetchall()
        ]
        # print(f"Loaded {len(messages)} messages from DB. Search: '{search_term}', Limit: {limit}, Offset: {offset}") # Debug
        return messages
    except sqlite3.Error as e:
        print(f"Database Error (load_messages_from_db): {e}")
        return []

def main() -> None:
    db_conn = None
    try:
        db_conn = init_db()
        app = ChatApp()
        app.mainloop()
    except sqlite3.Error as e:
        print(f"Database initialization error: {e}")
        return # Exit if DB can't be initialized
    except Exception as e:
        print(f"An unexpected error occurred during setup: {e}")
        if db_conn: db_conn.close()
        return
    
    try:
        while True:
            # Open the FIFO. This will block until a writer (the server) opens it.
            with open(FIFO_PATH, 'r') as fifo:
                print(f"FIFO opened. Listening for messages...")
    except FileNotFoundError:
        print(f"Critical Error: Named pipe {FIFO_PATH} was not found or was deleted during operation.")
        print("Please ensure the pipe exists and restart the application.")
    except IOError as e:
        print(f"IOError accessing FIFO: {e}")
    except KeyboardInterrupt:
        print("\nChat receiver stopped by user (Ctrl+C).")
    finally:
        # Note: The FIFO is not removed by this script automatically.
        # This allows the server to continue trying to write to it if this app restarts.
        # To fully clean up, manually remove /tmp/assembly_chat_fifo if desired.
        print("Exiting chat app receiver.")
        if db_conn: # Ensure db_conn was successfully assigned
            db_conn.close()
            print("Database connection closed.")


if __name__ == "__main__":
    main()
