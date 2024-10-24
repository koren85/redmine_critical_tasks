# app/controllers/critical_tasks_controller.rb
class CriticalTasksController < ApplicationController
  helper :sort
  include SortHelper

  before_action :require_login
  before_action :authorize_global

  def index
    @statuses = IssueStatus.all
    @selected_statuses = params[:status_ids] || []

    sort_init 'project_id', 'asc'
    sort_update %w(project_id status_id assigned_to_id start_date due_date)

    # Получаем итоговые даты для всех задач
    @final_dates = {}
    CustomValue.where(
      customized_type: 'Issue',
      custom_field_id: 81
    ).each do |cv|
      begin
        @final_dates[cv.customized_id] = cv.value.present? ? Date.parse(cv.value) : nil
      rescue
        @final_dates[cv.customized_id] = nil
      end
    end

    # Находим все задачи с заполненным кастомным полем
    marked_issues = Issue.visible
                         .joins(:custom_values)
                         .where(custom_values: {
                           custom_field_id: Setting.plugin_redmine_critical_tasks['custom_field_id'],
                           value: '1'
                         })

    # Собираем все связанные задачи
    related_issues_ids = Set.new

    marked_issues.each do |issue|
      if issue.parent_id.present?
        # Если это подзадача, добавляем родительскую задачу
        parent = Issue.find(issue.parent_id)
        related_issues_ids.add(parent.id)
        # Добавляем все подзадачи этого родителя
        Issue.where(parent_id: parent.id).each do |sibling|
          related_issues_ids.add(sibling.id)
        end
      else
        # Если это родительская задача, добавляем её
        related_issues_ids.add(issue.id)
        # Добавляем все её подзадачи
        Issue.where(parent_id: issue.id).each do |child|
          related_issues_ids.add(child.id)
        end
      end
    end

    # Получаем все связанные задачи одним запросом
    base_issues = Issue.visible
                       .includes(:status, :assigned_to, :project)
                       .where(id: related_issues_ids.to_a)

    if @selected_statuses.present?
      base_issues = base_issues.where(status_id: @selected_statuses)
    end

    # Создаем хэш для хранения итоговых дат родительских задач
    @parent_final_dates = {}
    base_issues.each do |issue|
      if issue.parent_id.nil? # если это родительская задача
        @parent_final_dates[issue.id] = @final_dates[issue.id]
      end
    end

    # Получаем отсортированный список задач
    @issues = sort_issues(base_issues)

    # Теперь, когда у нас есть список задач, находим проблемные
    current_date = Date.today

    # Задачи с прошедшей итоговой датой
    @past_date_issues = @issues.select do |issue|
      date = if issue.parent_id.nil?
               @final_dates[issue.id]
             else
               @parent_final_dates[issue.parent_id]
             end
      date && date < current_date
    end

    # Задачи с пустой итоговой датой
    @empty_date_issues = @issues.select do |issue|
      date = if issue.parent_id.nil?
               @final_dates[issue.id]
             else
               @parent_final_dates[issue.parent_id]
             end
      date.nil?
    end

    # Объединяем все проблемные задачи
    @problematic_issues = (@past_date_issues + @empty_date_issues).uniq

    # Создаем хэш для определения проблемных задач в представлении
    @issue_problems = {}
    @past_date_issues.each { |issue| @issue_problems[issue.id] = :past_date }
    @empty_date_issues.each { |issue| @issue_problems[issue.id] = :empty_date }

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

  private

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
      worksheet.autofilter = RubyXL::AutoFilter.new
      worksheet.autofilter.ref = "A1:I#{@issues.length + 1}"
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