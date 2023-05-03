# frozen_string_literal: true

class UsersAllowList < ActiveRecord::Base
  validates_presence_of :hashed_email
end

# == Schema Information
#
# Table name: users_allow_list
#
#  id                :bigint           not null, primary key
#  hashed_email      :integer          not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
# Indexes
#
#  index_users_allow_list_on_hashed_email (hashed_email) UNIQUE
#
