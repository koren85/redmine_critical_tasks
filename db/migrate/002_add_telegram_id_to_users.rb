class AddTelegramIdToUsers < ActiveRecord::Migration[5.2]
  def change
    add_column :users, :telegram_id, :string
    add_index :users, :telegram_id
  end
end