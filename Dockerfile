FROM ruby:3.1

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update -qq && apt-get install -y build-essential libpq-dev

# Install bundler
RUN gem install bundler

# Copy Gemfile and Gemfile.lock
COPY Gemfile Gemfile.lock ./

# Install ruby dependencies
RUN bundle install

# Copy the rest of the application
COPY . .

# Expose the port Sinatra runs on
EXPOSE 3010

# Command to start the application
CMD ["bundle", "exec", "ruby", "app.rb", "-o", "0.0.0.0"]
