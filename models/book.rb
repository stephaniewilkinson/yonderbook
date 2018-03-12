# frozen_string_literal: true

class Book < Sequel::Model
  many_to_one :user
end
