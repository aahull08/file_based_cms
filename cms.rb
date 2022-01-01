require "sinatra"
require "sinatra/reloader"
require "sinatra/content_for"
require "tilt/erubis"
require "redcarpet"
require "yaml"
require "bcrypt"
require 'fileutils'
require 'pry'

configure do
  enable :sessions
  set :session_secret, 'secret'
#  set :erb, :escape_html => true
end

def get_users
  users_path = if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/users.yml", __FILE__)
  else
    File.expand_path("../users.yml", __FILE__)
  end
  YAML.load_file(users_path)
end

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def check_if_signed_in
  unless session.key?(:username)
    session[:message] = "You must be signed in to do that."
    redirect "/"
  end
end

get "/" do
  @username = session[:username]
  pattern = File.join(data_path, "*")
  @files = Dir.glob(pattern).map do |path|
    File.basename(path)
  end
  
  erb :index, layout: :layout
end

def render_markdown(file_path)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  file_contents = File.read(file_path)
  markdown.render(file_contents)
end

get "/new" do
  check_if_signed_in
  erb :new, layout: :layout
end

get "/:file" do
  file_path = File.join(data_path, params[:file])

  if File.extname(file_path) == ".md"
    erb render_markdown(file_path)
  elsif File.extname(file_path) == ".txt"
    headers["Content-Type"] = "text/plain"
    File.read(file_path)
  else
    session[:message] = "#{params[:file]} does not exist."
    redirect "/"
  end
end

get "/:file/edit" do
  check_if_signed_in
  file_path = File.join(data_path, params[:file])
  @content = File.read(file_path)
  erb :edit, layout: :layout
end

post "/:file/destroy" do
  check_if_signed_in
  file_name = params[:file]
  file_path = File.join(data_path, file_name)
  
  File.delete(file_path)
  
  session[:message] = "#{file_name} was deleted"
  redirect "/"
end

def create_file_name(original_name)
  pattern = File.join(data_path, "*")
  files = Dir.glob(pattern).select do |path|
    File.basename(path)
  end
  files = files.map { |file| File.basename(file) }
  counter = 2
  extname = File.extname(original_name)
  basename = File.basename(original_name, ".*")
  new_file_name = "#{basename}(#{counter})#{extname}"
  while files.include?(new_file_name)
    files << new_file_name
    counter += 1
    new_file_name = "#{basename}(#{counter})#{extname}"
  end
  new_file_name
end

post "/:file/duplicate" do
  check_if_signed_in
  file_name = params[:file]
  file_path = File.join(data_path, file_name)
  new_file_name = create_file_name(file_name)
  FileUtils.cp file_path, "#{data_path}/#{new_file_name}"

  session[:message] = "#{file_name} was copied"
  redirect "/"
end

post "/new" do
  check_if_signed_in
  new_doc = params[:new_doc].to_s
  
  if new_doc.size == 0 || !new_doc.match?(/.+(.md|.txt)\z/)
    session[:message] = "Your document must have a name and be a .md or .txt document"
    status 422
    erb :new, layout: :layout
  else
    session[:message] = "#{new_doc} was created"
    File.new(data_path + "/#{new_doc}", "w")
    redirect "/"
  end
end

def correct_login?(username, password)
  users = get_users
  
  if users.key?(username)
    bcrypt_pw = BCrypt::Password.new(users[username])
    bcrypt_pw == password
  else
    false
  end
end

post "/users/signin" do
  username = params[:username]
  
  if correct_login?(username, params[:password])
    session[:message] = "Welcome!"
    session[:username] = username
    redirect "/"
  else
    session[:message] = "Invalid credentials."
    status 422
    erb :sign_in, layout: :layout
  end
end

def valid_new_username?(username)
  users = get_users
  return true unless users.key?(username)
end

def valid_password?(password)
  password.size > 0
end

def create_user(username, password)
  yaml_path = File.expand_path("../users.yml", __FILE__)
  password = BCrypt::Password.create(password).to_yaml.scan(/\$.+"/)[0][0..-2]
  updated_data = YAML.load_file yaml_path
  updated_data[username] = password
  File.open(yaml_path, 'w') { |file| file.write(updated_data.to_yaml) }
end

post "/users/signup" do
  username = params[:username]
  password = params[:password]
  
  if valid_new_username?(username) && valid_password?(password)
    session[:message] = "Welcome!"
    session[:username] = username
    create_user(username, password)
    redirect "/"
  elsif password.size < 4
    session[:message] = "The password must be at least 4 characters long"
  elsif username.size < 1
    session[:message] = "The username must be at least 2 characters long"
  else
    session[:message] = "That username is already in use."
  end

  status 422
  erb :sign_up, layout: :layout
end

post "/users/signout" do
  session[:message] = "You have been signed out."
  session.delete(:username)
  session.delete(:password)
  redirect "/"
end

post "/:file" do
  check_if_signed_in
  file_path = File.join(data_path, params[:file])
  
  File.write(file_path, params[:content])

  session[:message] = "#{params[:file]} has been updated."
  redirect "/"
end

get "/users/signin" do
  erb :sign_in, layout: :layout
end

get "/users/signup" do
  erb :sign_up, layout: :layout
end
# refractor duplicate
# test for duplicate
# test for signup

