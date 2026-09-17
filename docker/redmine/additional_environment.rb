# frozen_string_literal: true

# DMSF WebDAV middleware. WebDAV remains disabled until enabled in the plugin's
# Administration settings; enabling it requires an explicit security review.
require Rails.root.join('plugins/redmine_dmsf/lib/redmine_dmsf/webdav/custom_middleware')
config.middleware.insert_before ActionDispatch::Cookies, RedmineDmsf::Webdav::CustomMiddleware

config.log_level = :info
