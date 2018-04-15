# frozen_string_literal: true

# user has many books
class User < Sequel::Model
  one_to_many :books
end
