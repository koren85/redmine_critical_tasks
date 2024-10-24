$(document).ready(function() {
    $('.select2').select2({
        placeholder: 'Выберите статусы',
        allowClear: true
    });

    $('.expander').click(function() {
        var parentRow = $(this).closest('tr');
        var childRows = parentRow.nextUntil('tr.parent');
        childRows.toggle();
        $(this).toggleClass('collapsed');
    });

    // Добавляем hover эффект для групп задач
    $('.tree-table tr.parent').hover(
        function() {
            $(this).nextUntil('tr.parent').css('filter', 'brightness(95%)');
        },
        function() {
            $(this).nextUntil('tr.parent').css('filter', '');
        }
    );
});