# frozen_string_literal: true

desc "Run rubocop style and lint checks"
task :rubocop do
  sh("bundle exec rubocop -f progress -f offenses")
end
