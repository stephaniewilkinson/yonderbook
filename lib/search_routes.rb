# frozen_string_literal: true

# Anonymous search routes for users who connected Goodreads without an account
module SearchRoutes
  def handle_search_routes request
    require_goodreads_session request

    request.on 'shelves' do
      # route: GET /search/shelves
      request.get true do
        @shelves = Goodreads.fetch_shelves @goodreads_user_id
        view 'search/shelves'
      end

      request.on String do |shelf_name|
        @shelf_name = shelf_name
        @book_info = cached_or_fetch(@shelf_name.to_sym) { Goodreads.get_books(@shelf_name, @goodreads_user_id, @anon_access_token) }

        # route: GET /search/shelves/:name
        request.get true do
          @histogram_dataset = Goodreads.plot_books_over_time @book_info
          @ratings = Goodreads.rating_stats @book_info
          view 'shelves/show'
        end
      end
    end
  end
end
