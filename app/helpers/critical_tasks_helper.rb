module CriticalTasksHelper
  def render_telegram_notification_form
    return unless Setting.plugin_redmine_critical_tasks['telegram_enabled']

    content_tag(:div, class: 'telegram-notification-form') do
      form_tag(notify_responsible_critical_tasks_path, method: :post, id: 'notify-form') do
        content_tag(:div, class: 'notification-settings') do
          label_tag(l(:label_select_users)) +
            select_tag('user_ids[]',
                       options_from_collection_for_select(
                         available_telegram_users,
                         :id,
                         :name,
                         @selected_users
                       ),
                       multiple: true,
                       class: 'select2',
                       style: 'width: 300px;'
            ) +
            submit_tag(l(:button_notify_selected), class: 'button-small')
        end
      end
    end
  end

  def available_telegram_users
    User.active.where.not(telegram_id: nil)
  end
end