# lib/critical_tasks/issue_finder.rb
module CriticalTasks
  class IssueFinder
    def initialize(settings = Setting.plugin_redmine_critical_tasks)
      @settings = settings
    end

    def find_issues(selected_statuses = [], status_operator = '=', selected_users = [], user_operator = '=')
      Rails.cache.fetch(cache_key(selected_statuses, status_operator, selected_users, user_operator), expires_in: 5.minutes) do
        find_all_issues(selected_statuses, status_operator, selected_users, user_operator)
      end
    end

    private

    def cache_key(selected_statuses, status_operator, selected_users, user_operator)
      components = [
        'critical_tasks',
        'issues',
        @settings['custom_field_id'],
        status_operator,
        (selected_statuses || []).sort.join(','),
        user_operator,
        (selected_users || []).sort.join(','),
        Date.today.to_s
      ]
      components.join('/')
    end

    def find_all_issues(selected_statuses, status_operator, selected_users, user_operator)
      final_dates = load_final_dates
      base_issues = load_base_issues(selected_statuses, status_operator, selected_users, user_operator)
      parent_final_dates = create_parent_dates_hash(base_issues, final_dates)

      issues = base_issues
      problematic_issues = find_problematic_issues(issues, final_dates, parent_final_dates)

      {
        issues: issues,
        final_dates: final_dates,
        parent_final_dates: parent_final_dates,
        past_date_issues: problematic_issues[:past_date],
        empty_date_issues: problematic_issues[:empty_date],
        issue_problems: problematic_issues[:problems]
      }
    end

    def load_base_issues(selected_statuses, status_operator, selected_users, user_operator)

      Rails.logger.info "Starting load_base_issues with params:"
      Rails.logger.info "Selected users: #{selected_users.inspect}"
      Rails.logger.info "User operator: #{user_operator}"
      Rails.logger.info "Selected statuses: #{selected_statuses.inspect}"
      Rails.logger.info "Status operator: #{status_operator}"
      # Базовый запрос для получения задач с кастомным полем
      base_query = Issue.visible
                        .joins(:custom_values)
                        .where(custom_values: {
                          custom_field_id: @settings['custom_field_id'],
                          value: '1'
                        })
      Rails.logger.info "Base query SQL: #{base_query.to_sql}"
      # Получаем все связанные задачи без фильтров
      all_related_issues = collect_full_hierarchy(base_query)
      Rails.logger.info "All related issues count: #{all_related_issues.count}"

      filtered_issues = all_related_issues

      # Применяем фильтр по пользователям, если выбраны
      if selected_users.present?
        Rails.logger.info "Applying user filter"
        user_modified_issues = Issue.joins(:journals)
                                    .joins("INNER JOIN journal_details ON journal_details.journal_id = journals.id")
                                    .where(journals: { user_id: selected_users })
                                    .where(journal_details: {
                                      property: 'cf',
                                      prop_key: @settings['custom_field_id'],
                                      value: '1'
                                    })
                                    .distinct
                                    .pluck(:id)
        Rails.logger.info "Found user modified issues: #{user_modified_issues.inspect}"

        filtered_issues = if user_operator == '='
                            filtered_issues.where(id: user_modified_issues)
                          else
                            filtered_issues.where.not(id: user_modified_issues)
                          end
        Rails.logger.info "After user filter issues count: #{filtered_issues.count}"
      end

      # Применяем фильтр по статусам, если выбраны
      if selected_statuses.present?
        Rails.logger.info "Applying status filter"
        filtered_issues = case status_operator
                          when '='
                            filtered_issues.where(status_id: selected_statuses)
                          when '!'
                            filtered_issues.where.not(status_id: selected_statuses)
                          end
        Rails.logger.info "After status filter issues count: #{filtered_issues.count}"

      end

      # Собираем связанные задачи для отфильтрованных результатов
      result_ids = Set.new
      filtered_issues.each do |issue|
        result_ids.add(issue.id)
        if issue.parent_id.nil?
          # Для родительской задачи добавляем отфильтрованные подзадачи
          child_ids = filtered_issues.where(parent_id: issue.id).pluck(:id)
          child_ids.each { |id| result_ids.add(id) }
        else
          # Для подзадачи всегда добавляем родительскую задачу
          result_ids.add(issue.parent_id)
          # И отфильтрованные "сестринские" подзадачи
          sibling_ids = filtered_issues.where(parent_id: issue.parent_id).pluck(:id)
          sibling_ids.each { |id| result_ids.add(id) }
        end
      end

      Issue.visible
           .includes(:status, :assigned_to, :project)
           .where(id: result_ids.to_a)
    end

    def collect_full_hierarchy(base_query)
      issue_ids = Set.new

      base_query.find_each do |issue|
        if issue.parent_id.present?
          # Для подзадачи добавляем её саму, родителя и все подзадачи родителя
          issue_ids.add(issue.id)
          issue_ids.add(issue.parent_id)
          Issue.where(parent_id: issue.parent_id).pluck(:id).each { |id| issue_ids.add(id) }
        else
          # Для родительской добавляем её саму и все подзадачи
          issue_ids.add(issue.id)
          Issue.where(parent_id: issue.id).pluck(:id).each { |id| issue_ids.add(id) }
        end
      end

      Issue.visible
           .includes(:status, :assigned_to, :project)
           .where(id: issue_ids.to_a)
    end

    def load_final_dates
      CustomValue.where(
        customized_type: 'Issue',
        custom_field_id: 81
      ).each_with_object({}) do |cv, hash|
        hash[cv.customized_id] = parse_date(cv.value)
      end
    end

    def create_parent_dates_hash(issues, final_dates)
      issues.each_with_object({}) do |issue, hash|
        hash[issue.id] = final_dates[issue.id] if issue.parent_id.nil?
      end
    end

    def find_problematic_issues(issues, final_dates, parent_final_dates)
      current_date = Date.today
      past_date = []
      empty_date = []
      problems = {}

      issues.each do |issue|
        date = issue.parent_id.nil? ? final_dates[issue.id] : parent_final_dates[issue.parent_id]

        if date.nil?
          empty_date << issue
          problems[issue.id] = :empty_date
        elsif date < current_date
          past_date << issue
          problems[issue.id] = :past_date
        end
      end

      {
        past_date: past_date,
        empty_date: empty_date,
        problems: problems
      }
    end

    def parse_date(value)
      return nil unless value.present?
      Date.parse(value)
    rescue
      nil
    end
  end
end