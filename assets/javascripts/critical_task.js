$(document).ready(function() {
    console.log('Initializing filters...');
    // Инициализация select2 для статусов
    $('.select2[name="status_ids[]"]').select2({
        placeholder: 'Выберите статусы',
        allowClear: true,
        width: '300px'
    });

    // Инициализация select2 для пользователей в форме уведомлений
    $('.select2[name="user_ids[]"]').select2({
        placeholder: 'Выберите пользователей',
        allowClear: true,
        width: '300px'
    });

    // Инициализация select2 для пользователей в фильтре
    $('.select2[name="custom_field_user_ids[]"]').select2({
        placeholder: 'Выберите пользователей',
        allowClear: true,
        width: '300px'
    });


    // Инициализация select2 для операторов
    $('.status-operator, .user-operator').select2({
        minimumResultsForSearch: Infinity,
        width: '200px'
    });

    // Функционал сворачивания/разворачивания
    $('.expander').click(function() {
        var parentRow = $(this).closest('tr');
        var childRows = parentRow.nextUntil('tr.parent');
        childRows.toggle();
        $(this).toggleClass('collapsed');

        // Добавляем плавную анимацию
        $(this).css('transform', $(this).hasClass('collapsed') ? 'rotate(-90deg)' : 'rotate(0deg)');
    });

    // Hover эффект для групп задач
    $('.tree-table tr.parent').hover(
        function() {
            // Применяем эффект к родительской строке и всем её подзадачам
            $(this).css('filter', 'brightness(98%)');
            $(this).nextUntil('tr.parent').css('filter', 'brightness(95%)');
        },
        function() {
            // Убираем эффект при уходе курсора
            $(this).css('filter', '');
            $(this).nextUntil('tr.parent').css('filter', '');
        }
    );

    // Сохранение состояния фильтров
    $('#filters-form').on('submit', function() {
        var filterState = {
            statusOperator: $('select[name="status_operator"]').val(),
            statusIds: $('select[name="status_ids[]"]').val(),
            userOperator: $('select[name="user_operator"]').val(),
            customFieldUserIds: $('select[name="custom_field_user_ids[]"]').val()
        };
        localStorage.setItem('criticalTasksFilterState', JSON.stringify(filterState));
        return true;
    });
    // Восстановление состояния фильтров
    try {
        var savedState = JSON.parse(localStorage.getItem('criticalTasksFilterState'));
        if (savedState) {
            if (savedState.statusOperator) {
                $('select[name="status_operator"]').val(savedState.statusOperator).trigger('change');
            }
            if (savedState.statusIds) {
                $('select[name="status_ids[]"]').val(savedState.statusIds).trigger('change');
            }
            if (savedState.userOperator) {
                $('select[name="user_operator"]').val(savedState.userOperator).trigger('change');
            }
            if (savedState.customFieldUserIds) {
                $('select[name="custom_field_user_ids[]"]').val(savedState.customFieldUserIds).trigger('change');
            }
        }
    } catch (e) {
        console.error('Error restoring filter state:', e);
    }

    // Получаем параметры из URL
    var urlParams = new URLSearchParams(window.location.search);
    console.log('URL params:', Object.fromEntries(urlParams));
    var statusIds = urlParams.getAll('status_ids[]');
    var userIds = urlParams.getAll('user_ids[]');

    var customFieldUserIds = urlParams.getAll('custom_field_user_ids[]');
    var statusOperator = urlParams.get('status_operator');
    var userOperator = urlParams.get('user_operator');

    console.log('User IDs from URL:', customFieldUserIds);
    console.log('User operator from URL:', userOperator);

    // Восстанавливаем состояние фильтров
    if (statusIds.length) {
        $('select[name="status_ids[]"]').val(statusIds).trigger('change');
    }

    if (userIds.length) {
        $('select[name="user_ids[]"]').val(userIds).trigger('change');
    }

    if (customFieldUserIds.length) {
        console.log('Setting user IDs:', customFieldUserIds);
        $('select[name="custom_field_user_ids[]"]').val(customFieldUserIds).trigger('change');
    }

    if (statusOperator) {
        $('select[name="status_operator"]').val(statusOperator).trigger('change');
    }

    if (userOperator) {
        console.log('Setting user operator:', userOperator);
        $('select[name="user_operator"]').val(userOperator).trigger('change');
    }

// Обработка формы фильтров
    $('#status-filter-form, #user-filter-form').on('submit', function() {
        console.log('Form submitted');
        console.log('Selected users:', $('select[name="custom_field_user_ids[]"]').val());
        console.log('User operator:', $('select[name="user_operator"]').val());
        var formId = $(this).attr('id');
        var filterState = {
            statusOperator: $('select[name="status_operator"]').val(),
            statusIds: $('select[name="status_ids[]"]').val(),
            userOperator: $('select[name="user_operator"]').val(),
            customFieldUserIds: $('select[name="custom_field_user_ids[]"]').val()
        };

        // Сохраняем состояние фильтров
        localStorage.setItem('criticalTasksFilterState', JSON.stringify(filterState));
        return true;
    });

    // Восстанавливаем сохраненное состояние фильтров при загрузке
    try {
        var savedState = JSON.parse(localStorage.getItem('criticalTasksFilterState'));
        if (savedState && !statusIds.length && !customFieldUserIds.length) { // Применяем только если нет параметров в URL
            if (savedState.statusOperator) {
                $('select[name="status_operator"]').val(savedState.statusOperator).trigger('change');
            }
            if (savedState.statusIds) {
                $('select[name="status_ids[]"]').val(savedState.statusIds).trigger('change');
            }
            if (savedState.userOperator) {
                $('select[name="user_operator"]').val(savedState.userOperator).trigger('change');
            }
            if (savedState.customFieldUserIds) {
                $('select[name="custom_field_user_ids[]"]').val(savedState.customFieldUserIds).trigger('change');
            }
        }
    } catch (e) {
        console.error('Error restoring filter state:', e);
    }

    // Добавляем индикатор загрузки при отправке уведомлений
    $('#notify-form').on('submit', function() {
        $(this).find('input[type="submit"]').prop('disabled', true)
            .val('Отправка...');
        return true;
    });

    // Обработка кнопки очистки фильтров
    $('.button-clear').click(function(e) {
        e.preventDefault();
        localStorage.removeItem('criticalTasksFilterState');
        window.location.href = $(this).attr('href');
    });
});