function drop(event) {
    event.preventDefault();
    var data = event.dataTransfer.getData("text");
    var item = document.createElement("div");
    item.className = "item";
    item.innerHTML = data;
    var deleteIcon = document.createElement("i");
    deleteIcon.textContent = "X";
    //deleteIcon.className = "fas fa-trash";
    deleteIcon.addEventListener('click', function() {
        item.remove();
    });
    item.appendChild(deleteIcon);
    event.target.appendChild(item);
}

var items = document.querySelectorAll('.item');
items.forEach(function(item) {
    item.addEventListener('dragstart', function(event) {
        event.dataTransfer.setData("text", event.target.outerHTML);
    });
});