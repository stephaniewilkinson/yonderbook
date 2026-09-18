# frozen_string_literal: true

require_relative '../title_normalizer'

class Overdrive
  module Matching
    module_function

    def title_matches_exactly? product, target_title
      product_title = product['title']
      return false unless product_title

      normalized_overdrive = TitleNormalizer.normalize(product_title)
      normalized_goodreads = TitleNormalizer.normalize(target_title)
      return true if normalized_overdrive == normalized_goodreads
      return true if normalized_goodreads.start_with?(normalized_overdrive)
      return true if normalized_overdrive.start_with?(normalized_goodreads)

      false
    end

    def author_matches? product, target_author
      product_author = product.dig('primaryCreator', 'name')
      return false unless product_author
      return false if target_author.nil? || target_author.empty?

      author_last_name = target_author.split.last.downcase
      product_author.downcase.include?(author_last_name)
    end
  end
end
