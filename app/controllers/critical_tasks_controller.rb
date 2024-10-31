# app/controllers/critical_tasks_controller.rb
class CriticalTasksController < ApplicationController
  helper :sort
  include SortHelper
  helper :critical_tasks

  before_action :require_login
  before_action :authorize_global

  # В методе index контроллера
  # def index
  #   @statuses = IssueStatus.all
  #   @selected_statuses = params[:status_ids] || []
  #
  #   sort_init 'project_id', 'asc'
  #   sort_update %w(project_id status_id assigned_to_id start_date due_date)
  #
  #   finder_results = CriticalTasks::IssueFinder.new.find_issues(@selected_statuses)
  #
  #   # Сортировку выполняем здесь
  #   @issues = sort_issues(finder_results[:issues])
  #   @final_dates = finder_results[:final_dates]
  #   @parent_final_dates = finder_results[:parent_final_dates]
  #   @past_date_issues = finder_results[:past_date_issues]
  #   @empty_date_issues = finder_results[:empty_date_issues]
  #   @issue_problems = finder_results[:issue_problems]
  #
  #   @problematic_issues = (@past_date_issues + @empty_date_issues).uniq
  #
  #   respond_to do |format|
  #     format.html
  #     format.xlsx {
  #       send_data export_to_excel,
  #                 filename: "critical_tasks_#{Date.today.strftime('%Y%m%d')}.xlsx",
  #                 type: :xlsx,
  #                 disposition: 'attachment'
  #     }
  #   end
  # end

  def index
    @statuses = IssueStatus.all

    @selected_statuses = (params[:status_ids] || []).select(&:present?)
    @status_operator = params[:status_operator] || '='

    @selected_users = (params[:custom_field_user_ids] || []).select(&:present?)
    @user_operator = params[:user_operator] || '='

    Rails.logger.info "Selected users: #{@selected_users.inspect}"
    Rails.logger.info "User operator: #{@user_operator}"

    sort_init 'project_id', 'asc'
    sort_update %w(project_id status_id assigned_to_id start_date due_date)

    Rails.logger.info "Controller received params:"
    Rails.logger.info "Status IDs: #{params[:status_ids]}"
    Rails.logger.info "Status operator: #{params[:status_operator]}"
    Rails.logger.info "User IDs: #{params[:custom_field_user_ids]}"
    Rails.logger.info "User operator: #{params[:user_operator]}"

    # Альтернативный вариант выборки пользователей
    user_ids = Journal.joins("INNER JOIN journal_details ON journal_details.journal_id = journals.id")
                      .joins("INNER JOIN custom_values ON custom_values.customized_id = journals.journalized_id")
                      .where(journal_details: {
                        property: 'cf',
                        prop_key: Setting.plugin_redmine_critical_tasks['custom_field_id'],
                        value: '1'
                      })
                      .where(custom_values: { value: '1' })
                      .distinct
                      .pluck(:user_id)

    @custom_field_users = User.where(id: user_ids)
    Rails.logger.info "Available users: #{@custom_field_users.map { |u| [u.id, u.name] }}"

    sort_init 'project_id', 'asc'
    sort_update %w(project_id status_id assigned_to_id start_date due_date)

    finder_results = CriticalTasks::IssueFinder.new.find_issues(
      @selected_statuses,
      @status_operator,
      @selected_users,
      @user_operator
    )

    # finder_results = CriticalTasks::IssueFinder.new.find_issues(@selected_statuses, @status_operator)

    @issues = sort_issues(finder_results[:issues])
    @final_dates = finder_results[:final_dates]
    @parent_final_dates = finder_results[:parent_final_dates]
    @past_date_issues = finder_results[:past_date_issues]
    @empty_date_issues = finder_results[:empty_date_issues]
    @issue_problems = finder_results[:issue_problems]

    @problematic_issues = (@past_date_issues + @empty_date_issues).uniq

    respond_to do |format|
      format.html
      format.xlsx {
        send_data export_to_excel,
                  filename: "critical_tasks_#{Date.today.strftime('%Y%m%d')}.xlsx",
                  type: :xlsx,
                  disposition: 'attachment'
      }
    end
  end

  # app/controllers/critical_tasks_controller.rb

  def notify_responsible
    settings = Setting.plugin_redmine_critical_tasks
    return unless settings['telegram_enabled'] && params[:user_ids].present?

    selected_statuses = params[:status_ids] || []
    status_operator = params[:status_operator] || '='

    # finder_results = CriticalTasks::IssueFinder.new.find_issues(selected_statuses)
    finder_results = CriticalTasks::IssueFinder.new.find_issues(selected_statuses, status_operator)

    @past_date_issues = finder_results[:past_date_issues]
    @empty_date_issues = finder_results[:empty_date_issues]

    #Rails.logger.info "Found #{@past_date_issues.size} past date issues"
    #Rails.logger.info "Found #{@empty_date_issues.size} empty date issues"

    # Добавляем отладочную информацию для selected_users
    #Rails.logger.info "User IDs from params: #{params[:user_ids].inspect}"

    selected_users = User.where(id: params[:user_ids])
                         .where.not(telegram_id: [nil, ''])

    # Rails.logger.info "Found users before index_by: #{selected_users.map { |u| "#{u.id} (#{u.login})" }.join(', ')}"

    selected_users = selected_users.index_by(&:id)
    #Rails.logger.info "Selected users after index_by: #{selected_users.keys.inspect}"

    return if selected_users.empty?

    responsible_field_id = settings['responsible_custom_field_id']
    #Rails.logger.info "Responsible field ID: #{responsible_field_id}"
    return unless responsible_field_id.present?

    # Получим все возможные значения для поля ответственного
    custom_values = CustomValue.where(
      custom_field_id: responsible_field_id,
      customized_type: 'Issue'
    ).pluck(:customized_id, :value).to_h

    #Rails.logger.info "Custom field values mapping: #{custom_values.inspect}"

    notifications = {}
    problematic_issues = [@past_date_issues, @empty_date_issues].flatten.compact.uniq

    problematic_issues.each do |issue|
      # Проверяем значение в базе данных
      custom_value = CustomValue.where(
        customized_type: 'Issue',
        customized_id: issue.id,
        custom_field_id: responsible_field_id
      ).first

      #Rails.logger.info "Issue ##{issue.id} - custom value record: #{custom_value.inspect}"

      responsible_id = issue.custom_field_value(responsible_field_id)
      #Rails.logger.info "Issue ##{issue.id} - responsible_id from method: #{responsible_id.inspect}"

      if responsible_id.present?
        responsible_id = responsible_id.to_i
        #Rails.logger.info "Issue ##{issue.id} - responsible_id after conversion: #{responsible_id}"

        # Пробуем найти пользователя разными способами
        user = selected_users[responsible_id]
        direct_user = User.find_by(id: responsible_id)

        # Rails.logger.info "Issue ##{issue.id} - found user from selected: #{user&.inspect}"
        #Rails.logger.info "Issue ##{issue.id} - found user direct: #{direct_user&.inspect}"

        # Если пользователь не найден в selected_users, но существует в базе и есть в параметрах
        if user.nil? && direct_user && params[:user_ids].include?(direct_user.id.to_s)
          user = direct_user if direct_user.telegram_id.present?
        end

        if user&.telegram_id.present?
          problems = []
          problems << l(:label_past_date_issue) if @past_date_issues.include?(issue)
          problems << l(:label_empty_date_issue) if @empty_date_issues.include?(issue)

          notifications[user.telegram_id] ||= []
          notifications[user.telegram_id] << {
            issue: issue,
            problems: problems
          }
          Rails.logger.info "Added notification for user #{user.login} (#{user.telegram_id})"
        else
          Rails.logger.info "User #{responsible_id} not eligible for notification"
        end
      else
        Rails.logger.info "Issue ##{issue.id} has no responsible_id"
      end
    end

    Rails.logger.info "Prepared notifications for #{notifications.keys.size} users"

    success_count = 0
    failure_count = 0

    notifications.each do |telegram_id, issues|
      message = CriticalTasks::TelegramService.format_message(issues)
      if message.present?
        Rails.logger.info "Sending message to #{telegram_id}"
        if CriticalTasks::TelegramService.send_notification(telegram_id, message)
          success_count += 1
        else
          failure_count += 1
        end
      end
    end

    respond_to do |format|
      format.html {
        if success_count > 0
          if failure_count > 0
            flash[:warning] = l(:notice_notifications_partially_sent, count: failure_count)
          else
            flash[:notice] = l(:notice_notifications_sent)
          end
        else
          flash[:error] = l(:notice_no_notifications_sent)
        end
        redirect_to critical_tasks_path(user_ids: params[:user_ids])
      }
      format.js
    end
  rescue => e
    Rails.logger.error "Error in notify_responsible: #{e.message}\n#{e.backtrace.join("\n")}"
    respond_to do |format|
      format.html {
        flash[:error] = l(:error_sending_notifications)
        redirect_to critical_tasks_path(user_ids: params[:user_ids])
      }
      format.js { head :internal_server_error }
    end
  end

  private

  def build_notification_message(results)
    if results.values.any?
      if results.values.all?
        l(:notice_notifications_sent)
      else
        failed_count = results.values.count(false)
        l(:notice_notifications_partially_sent, count: failed_count)
      end
    else
      l(:notice_no_notifications_sent)
    end
  end

  private

  def send_notifications(notifications)
    notifications.map do |telegram_id, issues|
      begin
        message = CriticalTasks::TelegramService.format_message(issues)
        [telegram_id, CriticalTasks::TelegramService.send_notification(telegram_id, message)]
      rescue => e
        Rails.logger.error "Failed to send notification to #{telegram_id}: #{e.message}"
        [telegram_id, false]
      end
    end.to_h
  end

  def build_notification_message(results)
    if results.values.any?
      if results.values.all?
        l(:notice_notifications_sent)
      else
        failed_count = results.values.count(false)
        l(:notice_notifications_partially_sent, count: failed_count)
      end
    else
      l(:notice_no_notifications_sent)
    end
  end

  def get_color_value(key, default)
    settings = Setting.plugin_redmine_critical_tasks
    return default.gsub('#', '') if settings.nil? || !settings[key].present?
    settings[key].gsub('#', '')
  rescue
    default.gsub('#', '')
  end

  def apply_cell_style(cell, options = {})
    cell.change_border(:top, 'thin')
    cell.change_border(:bottom, 'thin')
    cell.change_border(:left, 'thin')
    cell.change_border(:right, 'thin')

    cell.change_fill(options[:bg_color]) if options[:bg_color]
    cell.change_font_bold(options[:bold]) if options[:bold]
    cell.change_horizontal_alignment(options[:align]) if options[:align]
    cell.change_vertical_alignment('center')
    cell.change_text_wrap(true)
    # Устанавливаем шрифт Arial для лучшей читаемости
    cell.change_font_name('Arial')

  end

  def sort_issues(issues)
    issues_by_parent = Hash.new { |h, k| h[k] = [] }
    parent_issues = []
    standalone_parents = []

    issues.each do |issue|
      if issue.parent_id.nil?
        if Issue.where(parent_id: issue.id).exists?
          parent_issues << issue
        else
          standalone_parents << issue
        end
      else
        issues_by_parent[issue.parent_id] << issue
      end
    end

    # Сортировка родительских задач
    parent_issues = sort_based_on_params(parent_issues)
    standalone_parents = sort_based_on_params(standalone_parents)

    # Собираем результат
    result = []
    parent_issues.each do |parent|
      result << parent
      children = issues_by_parent[parent.id]
      result.concat(sort_based_on_params(children))
    end
    result.concat(standalone_parents)

    result
  end

  def sort_based_on_params(issues)
    return issues unless params[:sort]

    sorted = case params[:sort]
             when 'project_id'
               issues.sort_by { |i| [i.project.name.downcase, i.id] }
             when 'status_id'
               issues.sort_by { |i| [i.status.name.downcase, i.id] }
             when 'assigned_to_id'
               issues.sort_by { |i| [(i.assigned_to&.name || '').downcase, i.id] }
             when 'start_date'
               issues.sort_by { |i| [i.start_date || Date.new(9999), i.id] }
             when 'due_date'
               issues.sort_by { |i| [i.due_date || Date.new(9999), i.id] }
             else
               issues.sort_by(&:id)
             end

    params[:sort_direction] == 'desc' ? sorted.reverse : sorted
  end


  def export_to_excel
    require 'rubyXL'
    require 'rubyXL/convenience_methods'

    # Определяем цвета с значениями по умолчанию
    colors = {
      parent: get_color_value('parent_task_color', '#f0f0f0'),
      child: get_color_value('subtask_color', '#ffffff'),
      past_date: get_color_value('error_date_past_color', '#ffebee'),
      empty_date: get_color_value('error_date_empty_color', '#fff3e0')
    }

    workbook = RubyXL::Workbook.new
    worksheet = workbook.worksheets[0]
    worksheet.sheet_name = 'Критичные задачи'

    # Заголовки
    headers = [
      l(:field_project),
      l(:field_parent_issue),
      l(:field_subject),
      l(:field_status),
      l(:field_assigned_to),
      l(:field_start_date),
      l(:field_due_date),
      l(:field_estimated_hours),
      l(:label_final_date)
    ]

    # Добавляем заголовки с серым фоном
    headers.each_with_index do |header, col|
      cell = worksheet.add_cell(0, col, header)
      apply_cell_style(cell, {
        bg_color: 'e6e6e6',
        bold: true,
        align: 'center'
      })
    end

    # Добавляем данные
    @issues.each_with_index do |issue, row|
      row_num = row + 1
      is_parent = issue.parent_id.nil?

      # Определяем цвет фона с безопасным получением значений
      bg_color = if @issue_problems[issue.id] == :past_date
                   get_color_value('error_date_past_color', '#ffebee')
                 elsif @issue_problems[issue.id] == :empty_date
                   get_color_value('error_date_empty_color', '#fff3e0')
                 else
                   is_parent ?
                     get_color_value('parent_task_color', '#f0f0f0') :
                     get_color_value('subtask_color', '#ffffff')
                 end

      final_date = if is_parent
                     @final_dates[issue.id]
                   else
                     @parent_final_dates[issue.parent_id]
                   end

      data = [
        issue.project.name,
        issue.parent_id,
        (is_parent ? issue.subject : "    └ #{issue.subject}"),
        issue.status.name,
        issue.assigned_to&.name,
        issue.start_date ? format_date(issue.start_date) : '',
        issue.due_date ? format_date(issue.due_date) : '',
        issue.estimated_hours,
        final_date ? format_date(final_date) : ''
      ]

      # Добавляем данные в ячейки
      data.each_with_index do |value, col|
        cell = worksheet.add_cell(row_num, col, value)

        style_options = {
          bg_color: bg_color,
          bold: is_parent
        }

        # Специальные стили для определенных столбцов
        case col
        when 5, 6, 8 # Даты (включая итоговую дату)
          style_options[:align] = 'center'
        when 7 # Числовые значения
          style_options[:align] = value.present? ? 'right' : 'left'
        else
          style_options[:align] = 'left'
        end

        apply_cell_style(cell, style_options)
      end
      end

    # Устанавливаем оптимальную ширину столбцов с учетом переноса текста
    column_widths = [20, 12, 60, 20, 25, 15, 15, 15, 15]
    column_widths.each_with_index do |width, index|
      worksheet.change_column_width(index, width)
    end

    # Устанавливаем высоту строки заголовков
    worksheet.change_row_height(0, 45)

    # Добавляем представление с замороженной панелью
    begin
      worksheet.sheet_views = RubyXL::WorksheetViews.new
      view = RubyXL::WorksheetView.new
      pane = RubyXL::Pane.new
      pane.top_left_cell = 'A2'
      pane.y_split = 1
      pane.state = 'frozen'
      view.pane = pane
      worksheet.sheet_views << view
    rescue => e
      Rails.logger.error "Failed to set frozen pane: #{e.message}"
    end

    # Добавляем автофильтр
    begin
      worksheet.auto_filter = RubyXL::AutoFilter.new
      worksheet.auto_filter.ref = "A1:I#{@issues.length + 1}"
    rescue => e
      Rails.logger.error "Failed to set autofilter: #{e.message}"
    end

    begin
      return workbook.stream.string
    rescue => e
      Rails.logger.error "Excel export error: #{e.message}\n#{e.backtrace.join("\n")}"
      raise
    end


  end


end