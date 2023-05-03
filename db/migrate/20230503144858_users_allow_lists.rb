# frozen_string_literal: true

class UsersAllowLists < ActiveRecord::Migration[7.0]
  def change
    create_table :users_allow_lists do |t|
      t.integer :hashed_email, null: false

      t.timestamps
    end

    add_index :users_allow_lists, %i[hashed_email], unique: true
  end
end
