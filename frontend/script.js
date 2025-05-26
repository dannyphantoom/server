function sayHello() {
    alert("Hello, World!");
}

function sendMessage() {
    const input = document.getElementById('message-input');
    const message = input.value.trim();
    if (!message) return;

    fetch('/message', {
        method: 'POST',
        headers: { 'Content-Type': 'text/plain' },
        body: message
    }).then(() => {
        input.value = '';
    }).catch(err => {
        console.error(err);
    });
}
