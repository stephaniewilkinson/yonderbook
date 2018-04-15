# frozen_string_literal: true

# a book belongs to a user
class Book < Sequel::Model
  many_to_one :user
end
