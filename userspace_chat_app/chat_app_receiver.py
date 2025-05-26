import os
import stat
import time

FIFO_PATH = "/tmp/assembly_chat_fifo"

def main():
    print(f"Attempting to use or create named pipe: {FIFO_PATH}")
    if not os.path.exists(FIFO_PATH):
        try:
            os.mkfifo(FIFO_PATH)
            print(f"Named pipe {FIFO_PATH} created.")
        except OSError as oe:
            print(f"Critical Error: Could not create FIFO: {oe}")
            print("Please check permissions or remove the conflicting file if it's not a FIFO.")
            return
    else:
        if not stat.S_ISFIFO(os.stat(FIFO_PATH).st_mode):
            print(f"Critical Error: {FIFO_PATH} exists but is not a FIFO.")
            print("Please remove the existing file and restart this application.")
            return
        print(f"Named pipe {FIFO_PATH} already exists and will be used.")

    print(f"Opening FIFO for reading: {FIFO_PATH}")
    print("Chat Application Receiver started.")
    print("Waiting for messages from the server...")
    print("--- Chat Log (Messages will appear below) ---")

    try:
        while True:
            # Open the FIFO. This will block until a writer (the server) opens it.
            with open(FIFO_PATH, 'r') as fifo:
                print(f"FIFO opened. Listening for messages...")
                while True:
                    message = fifo.readline()
                    if len(message) == 0: # Writer closed the pipe
                        print("(Server might have closed the connection or restarted. Re-opening FIFO...)")
                        # Brief pause before attempting to reopen, to avoid rapid spinning if server is down
                        time.sleep(0.5) 
                        break  # Break inner loop to reopen FIFO
                    
                    # Process the received message
                    processed_message = message.strip()
                    if processed_message: # Ensure it's not just an empty line from a keep-alive or similar
                        current_time = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())
                        print(f"[{current_time}] Server says: {processed_message}")
                    elif message == '\n': # If it was just a newline character (e.g. server sending newline after message)
                        pass # Silently ignore, or handle as a separator if desired
                    # else: an empty string from readline() with len 0 is handled above (writer closed)


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

if __name__ == "__main__":
    main() 