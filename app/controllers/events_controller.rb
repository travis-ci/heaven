# A controller to handle incoming webhook events
require "openssl"

class EventsController < ApplicationController
  include WebhookValidations

  before_filter :verify_incoming_webhook_address!
  skip_before_filter :verify_authenticity_token, :only => [:create]

  def create
    event    = request.headers["HTTP_X_GITHUB_EVENT"]
    delivery = request.headers["HTTP_X_GITHUB_DELIVERY"]

    if valid_events.include?(event)
      request.body.rewind
      data = request.body.read

      if verify_signature(data)
        Resque.enqueue(Receiver, event, delivery, data)
        render :status => 201, :json => "{}"
      else
        render :status => 401, :json => "{}"
      end
    else
      render :status => 404, :json => "{}"
    end
  end

  def valid_events
    %w{deployment deployment_status status ping}
  end

  def verify_signature(data)
    signature = 'sha1=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'), ENV['SECRET_TOKEN'], data)
    Rack::Utils.secure_compare(signature, request.headers['HTTP_X_HUB_SIGNATURE'])
  end
end
