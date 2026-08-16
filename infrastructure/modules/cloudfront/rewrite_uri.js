

function handler(event) {
    var request = event.request;
    var uri = request.uri;
    var last = uri.substring(uri.lastIndexOf('/')+1);

    if (last === '') {
        request.uri = uri + 'index.html'; // "/login/" -> "/login/index.html"
    } else if (last.indexOf('.') === -1) {
        request.uri = uri + '/index.html'; // "/login"  -> "/login/index.html"
    }

    return request;

}