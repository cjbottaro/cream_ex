FROM ruby:2.7-alpine

ADD Gemfile test/support/populate.rb ./
RUN bundle install
ENTRYPOINT [ "/bin/sleep" ]