# frozen_string_literal: true

# Normalizes book titles for comparison across different sources (Goodreads, OverDrive, etc.)
module TitleNormalizer
  module_function

  # Normalize title for comparison by removing series info, subtitles, and punctuation
  # Examples:
  #   "Parable of the Sower (Earthseed, #1)" => "parable of the sower"
  #   "The New Jim Crow: Mass Incarceration..." => "the new jim crow"
  #   "Caps for Sale: A Tale of a Peddler..." => "caps for sale"
  def normalize str
    # Remove series info in parentheses and subtitles after colons
    no_series = str.gsub(/\([^)]*\)/, '').split(':').first
    no_series.downcase.gsub(/[[:punct:]]/, '').gsub(/\s+/, ' ').strip
  end

  # Clean title for search queries (removes series info and subtitles, preserves case/punctuation)
  # Examples:
  #   "Parable of the Sower (Earthseed, #1)" => "Parable of the Sower"
  #   "The New Jim Crow: Mass Incarceration..." => "The New Jim Crow"
  #   "Caps for Sale: A Tale of a Peddler..." => "Caps for Sale"
  def clean_for_search str
    # Remove series info in parentheses and subtitles after colons
    str.gsub(/\([^)]*\)/, '').split(':').first.strip
  end
end
