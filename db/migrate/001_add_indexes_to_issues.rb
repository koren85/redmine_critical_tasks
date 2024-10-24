class AddIndexesToIssues < ActiveRecord::Migration[5.2]
  def change
    add_index :issues, :parent_id unless index_exists?(:issues, :parent_id)
    add_index :custom_values, [:customized_type, :customized_id, :custom_field_id],
              name: 'index_custom_values_on_customized_and_field' unless
      index_exists?(:custom_values, [:customized_type, :customized_id, :custom_field_id],
                    name: 'index_custom_values_on_customized_and_field')
  end
end