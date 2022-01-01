ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require "fileutils"

require_relative "../cms"


class AppTest < Minitest::Test
  include Rack::Test::Methods
  
  def setup
    FileUtils.mkdir_p(data_path)
  end
  
  def teardown
    FileUtils.rm_rf(data_path)
  end

  def create_document(name, content = "")
    File.open(File.join(data_path, name), "w") do |file|
      file.write(content)
    end
  end
  
  def app 
    Sinatra::Application
  end
  
  def session
    last_request.env["rack.session"]
  end
  
  def admin_session
    { "rack.session" => { username: "admin" } }
  end
  
  def test_index
    create_document("about.md")
    create_document("changes.txt")
    create_document("history.txt")
    
    get "/"
    
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes(last_response.body, "about.md")
    assert_includes(last_response.body, "changes.txt")
    assert_includes(last_response.body, "history.txt")
  end
  
  def test_changes_txt
    create_document("changes.txt", "content to test")

    
    get "/changes.txt"
    
    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-Type"]
    assert_equal "content to test", last_response.body
  end
  
  def test_history_txt
    create_document("history.txt", "Ruby 0.95 released")
    
    get "/history.txt"
    
    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-Type"]
    assert_includes last_response.body, "Ruby 0.95 released"
  end
  
  def test_file_missing_error
    get "/nofile.ext"
    
    assert_equal 302, last_response.status
    assert_equal "nofile.ext does not exist.", session[:message]
  end
  
  def test_markdown
    create_document("about.md", "<h1>Ruby is...</h1>")
    
    get "/about.md"
    
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes(last_response.body, "<h1>Ruby is...</h1>")
  end
  
  def test_editing_document
    create_document("changes.txt")
    
    get "/changes.txt/edit", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<textarea"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_editing_document_signed_out
    create_document "changes.txt"

    get "/changes.txt/edit"

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end
  
  def test_updating_document
    post "/changes.txt", {content: "new content"}, admin_session

    assert_equal 302, last_response.status
    assert_equal "changes.txt has been updated.", session[:message]

    get "/changes.txt"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "new content"
  end
  
  def test_updating_document_signed_out
    post "/changes.txt"
    
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end
  
  def test_view_new_document_form
    get "/new", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<input"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_view_new_document_form_signed_out
    get "/new"

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end
  
  def test_create_new_document
    post "/new", {new_doc: "test.txt"}, admin_session
    
    assert_equal 302, last_response.status
    assert_equal "test.txt was created", session[:message]


    get "/"
    assert_includes last_response.body, "test.txt"
  end
  
  def test_create_new_document_signed_out
    post "/new", {file: "test.txt"}

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_create_new_document_without_filename
    post "/new", {file: ""}, admin_session

    assert_equal 422, last_response.status
    assert_includes last_response.body, "Your document must have a name and be a .md or .txt document"
  end
  
  def test_create_new_document_invalid_name
    post "/new", {file: "test"}, admin_session

    assert_equal 422, last_response.status
    assert_includes last_response.body, "Your document must have a name and be a .md or .txt document"
  end
  def test_deleting_document
    create_document("test.txt")

    post "/test.txt/destroy" , {}, admin_session
    assert_equal 302, last_response.status
    assert_equal "test.txt was deleted", session[:message]

    get "/"
    refute_includes last_response.body, %q(href="/test.txt") 
  end
  
  def test_deleting_document_signed_out
    create_document("test.txt")

    post "/test.txt/destroy"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_signin_form
    get "/users/signin"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<input"
    assert_includes last_response.body, %q(<button type="submit")
  end
  
  def test_signin
    post "/users/signin", username: "admin", password: "secret"
    assert_equal 302, last_response.status
    assert_equal "Welcome!", session[:message]
    assert_equal "admin", session[:username]
    
    get last_response["Location"]
    assert_includes last_response.body, "Signed in as admin"
  end
  
  def test_signin_with_bad_credentials
    post "/users/signin", username: "guest", password: "shhhh"
    assert_equal 422, last_response.status
    assert_nil session[:username]
    assert_includes last_response.body, "Invalid credentials."
  end
  
  def test_signout
    get "/", {}, admin_session
    assert_includes last_response.body, "Signed in as admin"

    post "/users/signout"
    assert_equal "You have been signed out.", session[:message]
    
    get last_response["Location"]
    assert_nil session[:username]
    assert_includes last_response.body, "Sign In"
  end
end
