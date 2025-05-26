# Project Notes

## Overview

This project consists of a small HTTP server written in x86-64 assembly (backend) and a frontend web interface. The server serves static files from the `frontend` directory and handles message storage.

## Functionality

- **Frontend**:
    - Users interact with a web page (served from `frontend/index.html`) that includes a message bar, similar to a chat application.
    - Users can type messages and send them via the interface.
    - The frontend (`script.js`) sends messages to the backend via a POST request to `/message`.

- **Backend (Assembly Server - `backend/server.asm`)**:
    - Listens on port 8080.
    - **Static File Serving (GET Requests)**:
        - Parses GET requests to determine the requested file path (e.g., `/`, `/index.html`, `/style.css`).
        - Constructs the full file path relative to the `frontend/` directory.
        - Determines the correct `Content-Type` based on file extension (`.html`, `.css`, `.js`). Defaults to `text/html`.
        - Sends HTTP/1.1 200 OK responses with appropriate headers:
            - `Content-Type: <type>; charset=utf-8`
            - `Connection: close` (server closes connection after response).
        - Serves the file content in chunks.
        - **Error Handling**: Sends a proper HTTP/1.1 404 Not Found response (with an HTML error page) if a requested file is not found or cannot be opened.
    - **Message Storage (POST Requests to `/message`)**:
        - Parses the POST request to extract the message body.
        - Appends the received message, followed by a newline, to `messages.txt` on the local server host.
        - Sends an HTTP/1.1 200 OK response (text/plain) indicating the message was received.

## Building

Run `make` to assemble and link the server. This will also generate `constants.txt` which contains numeric values for system calls and other constants.

```
make
```

Use `make clean` to remove generated files.

## Running

The resulting binary (`server`) listens on port **8080**. Root privileges may be required to bind the port:

```
sudo ./server
```

Open `http://localhost:8080` in your browser to view `frontend/index.html`. POST requests to `/message` will be appended to `messages.txt`.

## Key Implementation Details & Notes for Future Agents

- The backend is implemented entirely in x86-64 assembly (NASM syntax).
- The server aims for basic HTTP/1.1 compliance for GET and POST requests.
- GET request handling has been significantly refactored for clarity and correctness, including robust path parsing and error handling (404 responses).
- All successful HTTP responses from the server now include `Connection: close`.
- The frontend is responsible for collecting user messages and sending them to the backend.
- All messages are stored persistently in `messages.txt` on the server.
- The assembly code manages socket operations, file I/O, and HTTP response construction directly using Linux syscalls.
- Key files:
    - `backend/server.asm`: The core assembly server logic.
    - `frontend/index.html`: Main HTML page.
    - `frontend/script.js`: Client-side logic for sending messages.
    - `frontend/style.css`: Styles for the frontend.
    - `Makefile`: Build script.
    - `messages.txt`: Stores user messages (created by the server). 