import os
import stat
import time
import sqlite3
import threading
import queue
import tkinter as tk
from tkinter import ttk, messagebox

FIFO_PATH = "/tmp/assembly_chat_fifo"
DB_PATH = os.path.join(os.path.dirname(__file__), "chat_history.db")


class ChatDatabase:
    """Simple wrapper around SQLite for storing chat messages."""

    def __init__(self, path: str = DB_PATH):
        self.conn = sqlite3.connect(path)
        self._init_db()

    def _init_db(self) -> None:
        with self.conn:
            self.conn.execute(
                """
                CREATE TABLE IF NOT EXISTS messages (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp TEXT NOT NULL,
                    message_content TEXT NOT NULL
                )
                """
            )

    def add_message(self, timestamp: str, message: str) -> None:
        with self.conn:
            self.conn.execute(
                "INSERT INTO messages(timestamp, message_content) VALUES(?, ?)",
                (timestamp, message),
            )

    def get_all_messages(self):
        cur = self.conn.cursor()
        cur.execute(
            "SELECT timestamp, message_content FROM messages ORDER BY id ASC"
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
        for ts, msg in self.db.get_all_messages():
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


def main() -> None:
    app = ChatApp()
    app.mainloop()


if __name__ == "__main__":
    main()
