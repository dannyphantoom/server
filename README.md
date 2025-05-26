# Assembly Web Server

This project is a small HTTP server written largely in x86-64 assembly. It serves static files from the `frontend` directory and stores POSTed messages in `messages.txt`.

## Building

Run `make` to assemble and link the server. This will also generate `constants.txt` which contains numeric values for system calls and other constants.

```
make
```

Use `make clean` to remove generated files.

## Running

The resulting binary listens on port **8080**. Root privileges may be required to bind the port:

```
sudo ./server
```

Open `http://localhost:8080` in your browser to view `frontend/index.html`. POST requests to `/message` will be appended to `messages.txt`.
