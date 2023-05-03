# frozen_string_literal: true

class UsersAllowList < ActiveRecord::Migration[7.0]
  def change
    create_table :users_allow_list do |t|
      t.integer :hashed_email, null: false

      t.timestamps
    end

    add_index :users_allow_list, %i[hashed_email], unique: true
  end
end
