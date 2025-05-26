# Project Notes

## Overview

This project consists of a small HTTP server written in x86-64 assembly (backend), a frontend web interface, and a separate user-space chat application. The server serves static files and relays user messages from the frontend to the chat application via a named pipe (FIFO).

## Architecture

1.  **Frontend (`frontend/`)**: HTML/CSS/JS interface where users type and send messages.
2.  **Assembly Server (`backend/server.asm`)**: Listens for HTTP requests.
    *   Serves static files from `frontend/` for GET requests.
    *   For POST requests to `/message` containing user messages, it writes the message to a named pipe.
3.  **Named Pipe (FIFO)**: Acts as an IPC mechanism. Path: `/tmp/assembly_chat_fifo`.
4.  **User-Space Chat Application (`userspace_chat_app/chat_app_receiver.py`)**: A Python application that reads messages from the named pipe.
    *   Currently, it prints messages to the console.
    *   Future goal: Develop this into a graphical chat application (like WhatsApp) that stores messages.

## Functionality

- **Frontend**:
    - Users interact with a web page (served from `frontend/index.html`) that includes a message bar.
    - `script.js` sends messages to the assembly server via a POST request to `/message`.

- **Backend (Assembly Server - `backend/server.asm`)**:
    - Listens on port 8080.
    - **Static File Serving (GET Requests)**:
        - Parses GET requests, constructs file paths relative to `frontend/`.
        - Determines `Content-Type` and sends HTTP/1.1 200 OK responses with `Content-Type: <type>; charset=utf-8` and `Connection: close` headers.
        - Serves file content in chunks.
        - **Error Handling**: Sends HTTP/1.1 404 Not Found response if a file is not found.
    - **Message Relaying (POST Requests to `/message`)**:
        - Parses the POST request to extract the message body.
        - **Writes the received message (and a newline) to the named pipe `/tmp/assembly_chat_fifo`.**
        - Sends an HTTP/1.1 200 OK response (text/plain) to the frontend.

- **User-Space Chat Application (`userspace_chat_app/chat_app_receiver.py`)**:
    - Creates the named pipe `/tmp/assembly_chat_fifo` if it doesn't exist.
    - Listens for messages on the pipe.
    - **Currently**: Prints received messages with a timestamp to the console.
    - **Future**: To be developed into a graphical application for message display and storage.

## Building

- **Assembly Server**: Run `make` in the root directory to assemble and link the server (`backend/server.asm`).
  ```
  make
  ```
  Use `make clean` to remove generated files.
- **User-Space Chat App**: No build step required for the current Python script.

## Running

1.  **Start the User-Space Chat Application Receiver**:
    Open a terminal and run:
    ```sh
    python userspace_chat_app/chat_app_receiver.py
    ```
    This application must be running to create/listen on the named pipe before the server attempts to write to it.

2.  **Start the Assembly Server**:
    Open another terminal. The server binary listens on port **8080**. Root privileges may be required to bind the port:
    ```sh
    sudo ./server
    ```

3.  **Access the Frontend**:
    Open `http://localhost:8080` in your browser to view `frontend/index.html`.
    Messages sent from the frontend will be relayed by the assembly server to the `chat_app_receiver.py` console.

## Key Implementation Details & Notes for Future Agents

- **IPC**: Communication between the assembly server and the user-space chat app uses a **Named Pipe (FIFO)** at `/tmp/assembly_chat_fifo`.
- The assembly backend (`server.asm`) now acts as a message relay for POSTed messages, forwarding them to the FIFO instead of writing to `messages.txt`.
- The `userspace_chat_app/chat_app_receiver.py` is currently a basic console logger for messages received via the FIFO. The graphical UI and persistent storage are future development tasks.
- The backend is implemented entirely in x86-64 assembly (NASM syntax).
- The server aims for basic HTTP/1.1 compliance for GET and POST requests.
- GET request handling includes path parsing, content type determination, and 404 error responses. All HTTP responses include `Connection: close`.
- The assembly code manages socket operations, file I/O (including FIFO operations), and HTTP response construction directly using Linux syscalls.
- Key files:
    - `backend/server.asm`: The core assembly server logic (HTTP handling, FIFO writing).
    - `userspace_chat_app/chat_app_receiver.py`: User-space application for receiving messages via FIFO.
    - `frontend/index.html`, `script.js`, `style.css`: Frontend components.
    - `Makefile`: Build script for the assembly server.
    - `/tmp/assembly_chat_fifo`: Named pipe for IPC (created by `chat_app_receiver.py`).
    - `messages.txt`: No longer used for primary message storage by the server. 