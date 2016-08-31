FROM ruby:2.2.4
RUN apt-get update -qq && apt-get install -y build-essential libpq-dev nodejs
#RUN echo 'gem: --no-ri --no-rdoc' > ~/.gemrc

# Rubygems and bundler
#RUN gem update --system --no-ri --no-rdoc
RUN gem install bundler -v 1.11.2 --no-ri --no-rdoc

ENV APP_HOME /yagpi2
RUN mkdir $APP_HOME
WORKDIR $APP_HOME

ADD Gemfile $APP_HOME/Gemfile
ADD Gemfile.lock $APP_HOME/Gemfile.lock
RUN bundle install
ADD . $APP_HOME

EXPOSE 3000
CMD bundle exec ruby app.rb -p 3000