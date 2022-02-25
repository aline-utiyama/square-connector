require 'base64'
require 'digest/sha1'
require 'httparty'
require 'json'
require 'uri'
require 'net/http'
require 'openssl'
require 'date'

def lambda_handler(event:, context:)
  
  # Sample pure Lambda function

  # Parameters
  # ----------
  # event: Hash, required
  #     API Gateway Lambda Proxy Input Format
  #     Event doc: https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html#api-gateway-simple-proxy-for-lambda-input-format

  # context: object, required
  #     Lambda Context runtime methods and attributes
  #     Context doc: https://docs.aws.amazon.com/lambda/latest/dg/ruby-context.html

  # Returns
  # ------
  # API Gateway Lambda Proxy Output Format: dict
  #     'statusCode' and 'body' are required
  #     # api-gateway-simple-proxy-for-lambda-output-format
  #     Return doc: https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html

  #  begin
  #    response = HTTParty.get('http://checkip.amazonaws.com/')
  #  rescue HTTParty::Error => error
  #    puts error.inspect
  #    raise error
  #  end

  @bm_key = "Bearer #{ENV['BM_KEY']}"
  @square_api_key = "Bearer #{ENV['SQUARE_KEY']}"
  @square_url = "#{ENV['SQUARE_URL']}"
  @bm_source_id = ENV['BM_SOURCE_ID']
  @webhook_signature_key = ENV['WEBHOOK_SIGNATURE_KEY']

  # Get the JSON body and HMAC-SHA1 signature of the incoming POST request
  callback_body = event['body']
  callback_signature = event['headers']['X-Square-Signature']

  # The URL that this server is listening on (e.g., 'http://example.com/events')
  # Note that to receive notifications from Square, this cannot be a localhost URL
  @webhook_url = ENV['WEBHOOK_URL']

  # Validate the signature
  if !is_valid_callback(callback_body, callback_signature)

	  # Fail if the signature is invalid
    puts 'Webhook event with invalid signature detected!'
    return
  end
         
  if !event['body'].nil?
    body = JSON.parse(event['body'])

    if body.has_key?('type')
      case body['type']
      when 'customer.created'
        customer_created(body)
      when 'customer.updated'
        customer_updated(body)
      when 'customer.deleted'
        customer_deleted(body)
      when 'catalog.version.updated'
        catalog_version_updated
      when 'subscription.created'
        subscription_created(body)
      when 'subscription.updated'
        subscription_updated(body)
      end
    end
  end
  
  { statusCode: 200, body: JSON.generate('Ok') }
end

# Validates HMAC-SHA1 signatures included in webhook notifications to ensure notifications came from Square
def is_valid_callback(callback_body, callback_signature)

  # Combine your webhook notification URL and the JSON body of the incoming request into a single string
  string_to_sign = @webhook_url + callback_body

  # Generate the HMAC-SHA1 signature of the string, signed with your webhook signature key
  string_signature = Base64.strict_encode64(OpenSSL::HMAC.digest('sha1', @webhook_signature_key, string_to_sign))

  # Hash the signatures a second time (to protect against timing attacks)
  # and compare them
  return Digest::SHA1.base64digest(string_signature) == Digest::SHA1.base64digest(callback_signature)
end

def customer_created(body)
  customer = body['data']['object']['customer']
  name = "#{customer['given_name']} #{customer['family_name']}"
  email = customer['email_address']
  oid = customer['id']
  created = customer['created_at']
  created_at = Date.parse(created)
  
  puts "Creating customer..."
  url = URI("https://api.baremetrics.com/v1/#{@bm_source_id}/customers")
  
  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true
  
  request = Net::HTTP::Post.new(url)
  request["Accept"] = 'application/json'
  request["Content-Type"] = 'application/json'
  request["Authorization"] = @bm_key
  request.body = "{\"created\":\"#{created_at.to_time.to_i}\",\"oid\":\"#{oid}\",\"name\":\"#{name}\",\"email\":\"#{email}\"}"
  
  response = http.request(request)
  puts response.read_body

  if response.is_a?(Net::HTTPOK)
    puts " Customer created!"
  else
    puts "Something Wrong..."
  end
end

def customer_updated(body)
  customer = body['data']['object']['customer']
  name = "#{customer['given_name']} #{customer['family_name']}"
  email = customer['email_address']
  oid = customer['id']
  created = customer['created_at']
  created_at = Date.parse(created)
  
  puts "Updating customer..."
  
  url = URI("https://api.baremetrics.com/v1/#{@bm_source_id}/customers/#{oid}")

  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true
  
  request = Net::HTTP::Put.new(url)
  request["Accept"] = 'application/json'
  request["Content-Type"] = 'application/json'
  request["Authorization"] = @bm_key
  request.body = "{\"name\":\"#{name}\",\"email\":\"#{email}\",\"created\":\"#{created_at.to_time.to_i}\"}"

  response = http.request(request)
  puts response.read_body

  if response.is_a?(Net::HTTPOK)
    puts "Customer updated!"
  elsif response.is_a?(Net::HTTPNotFound)
    customer_created(body)
  else
    puts "Something Wrong..."
  end
end

def customer_deleted(body)
  customer = body['data']['object']['customer']
  oid = customer['id']

  #Check if customer has subscription

  url = URI("https://api.baremetrics.com/v1/#{@bm_source_id}/subscriptions?customer_oid=#{oid}")

  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true

  request = Net::HTTP::Get.new(url)
  request["Accept"] = 'application/json'
  request["Authorization"] = @bm_key

  response = http.request(request)
  puts response.read_body

  if response.is_a?(Net::HTTPOK)
    
    bm_body = JSON.parse(response.read_body)

    bm_customer_subscriptions = bm_body['subscriptions']

    if !bm_customer_subscriptions.empty?
      bm_customer_subscriptions.each do |subscription|
        puts subscription['oid']
        deleted_subscription(subscription['oid'])
      end
    end

    puts "Deleting customer..."
    url = URI("https://api.baremetrics.com/v1/#{@bm_source_id}/customers/#{oid}")

    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    
    request = Net::HTTP::Delete.new(url)
    request["Accept"] = 'application/json'
    request["Authorization"] = @bm_key
    
    response = http.request(request)
    puts response.read_body
    puts response

    if response.is_a?(Net::HTTPAccepted)
      puts "Customer deleted."
    else
      puts "Something Wrong..."
    end
  else
    puts "Something Wrong..."
  end
end

def catalog_version_updated
  
  puts "Catalog Version Updated"
  
  bm_plans_id_list
  
  # List Square Plans
  url = URI("#{@square_url}/v2/catalog/list")

  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true
  
  request = Net::HTTP::Get.new(url)
  request["Square-Version"] =  '2022-01-20'
  request["Accept"] = 'application/json'
  request["Authorization"] = @square_api_key
  
  response = http.request(request)
  body = JSON.parse(response.read_body)
  
  body['objects'].each do |value|
    
    plan_oid = value['id']
    plan_name = value['subscription_plan_data']['name']
    trial_duration = 0
    trial_duration_unit = ""
    amount = 0
    cadence = ""
    currency = ""
    interval = ""
    interval_count = 0
    
    value['subscription_plan_data']['phases'].each do |phase|
      
      if phase['ordinal'] == 0
        if phase['periods']
          trial_periods = phase['periods']
        else
          trial_periods = 0
        end
        
        trial_cadence = phase['cadence']
        
        case trial_cadence
        when "DAILY"
            trial_duration_unit = "day"
            trial_duration = trial_periods
        when "WEEKLY"
            trial_duration_unit = 'day'
            trial_duration = trial_periods * 7
        when "MONTHLY"
            trial_duration_unit = 'month'
            trial_duration = trial_periods
        end
      end
      
      if phase['ordinal'] == 1
      
        amount = phase['recurring_price_money']['amount']
        currency = phase['recurring_price_money']['currency']
        cadence = phase['cadence']
          
        case cadence
        when "WEEKLY"
            interval = 'day'
            interval_count = 7
        when "EVERY_TWO_WEEKS"
            interval = 'day'
            interval_count = 14
        when "MONTHLY"
            interval = "month"
            interval_count = 1
        when "QUARTERLY"
            interval = "month"
            interval_count = 3
        when "EVERY_SIX_MONTHS"
            interval = "month"
            interval_count = 6
        when "ANNUAL"
            interval = 'year'
            interval_count = 1
        end
      end
    end
    
    #Create plan if doesnt exist
    if !@bm_plan_ids.include?(plan_oid)
      
      url = URI("https://api.baremetrics.com/v1/#{@bm_source_id}/plans")

      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true
      
      request = Net::HTTP::Post.new(url)
      request["Accept"] = 'application/json'
      request["Content-Type"] = 'application/json'
      request["Authorization"] = @bm_key
      
      if trial_duration.zero? || trial_duration.nil?
          puts "#{plan_name} Doesnt have trial period."
          request.body = "{\"oid\":\"#{plan_oid}\",\"name\":\"#{plan_name}\",\"currency\":\"#{currency}\",\"amount\":#{amount},\"interval\":\"#{interval}\",\"interval_count\":#{interval_count}}"
      else
          puts "#{plan_name} Have trial period!"
          request.body = "{\"trial_duration\":#{trial_duration},\"trial_duration_unit\":\"day\",\"oid\":\"#{plan_oid}\",\"name\":\"#{plan_name}\",\"currency\":\"#{currency}\",\"amount\":#{amount},\"interval\":\"#{interval}\",\"interval_count\":#{interval_count}}"
      end
      
      response = http.request(request)
      puts response.read_body.force_encoding("utf-8")

      if response.is_a?(Net::HTTPOK)
        puts "Plan created!"
      else
        puts "Something Wrong..."
      end 
    else
      bm_plan = @bm_plans_list.find {|key| key['oid'] == plan_oid}
      
      if plan_name != bm_plan['name']
        puts "Name not equal."
        url = URI("https://api.baremetrics.com/v1/#{@bm_source_id}/plans/#{plan_oid}")

        http = Net::HTTP.new(url.host, url.port)
        http.use_ssl = true
        
        request = Net::HTTP::Put.new(url)
        request["Accept"] = 'application/json'
        request["Content-Type"] = 'application/json'
        request["Authorization"] = @bm_key
        request.body = "{\"name\":\"#{plan_name}\"}"
        
        response = http.request(request)
        puts response.read_body
        
        if response.is_a?(Net::HTTPOK)
          puts "Plan name updated!"
        else
          puts "Something Wrong..."
        end 
      else
        puts "Name equal."
      end
    end
  end
end

def bm_plans_id_list
  @bm_plan_ids = []
  @bm_plans_hash = {}
  
  url = URI("https://api.baremetrics.com/v1/#{@bm_source_id}/plans")

  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true
  
  request = Net::HTTP::Get.new(url)
  request["Accept"] = 'application/json'
  request["Authorization"] = @bm_key
  
  response = http.request(request)
  
  body = JSON.parse(response.read_body)
  
  body['plans'].each do |plan|
    @bm_plan_ids << plan['oid']
  end
  
  @bm_plans_list = body['plans']
  @bm_plan_ids
end

def subscription_created(body)
  puts "Creating Subscription..."
  
  subscription = body['data']['object']['subscription']
  
  oid = subscription['id']
  plan_oid = subscription['plan_id']
  customer_oid = subscription['customer_id']
  started_at = subscription['start_date']
  started_date = Date.parse(started_at)
  
  status = subscription['status']
  
  if status == "ACTIVE"
    active = true
  else
    active = false
  end
  
  url = URI("https://api.baremetrics.com/v1/#{@bm_source_id}/subscriptions")

  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true
  
  request = Net::HTTP::Post.new(url)
  request["Accept"] = 'application/json'
  request["Content-Type"] = 'application/json'
  request["Authorization"] = @bm_key
  request.body = "{\"quantity\":1,\"oid\":\"#{oid}\",\"started_at\":\"#{started_date.to_time.to_i}\",\"plan_oid\":\"#{plan_oid}\",\"customer_oid\":\"#{customer_oid}\"}"
  
  response = http.request(request)
  puts response.read_body

  if response.is_a?(Net::HTTPOK)
    puts "Subscription Created!"
  else
    puts "Something Wrong..."
  end
end

def subscription_updated(body)
  puts "Updating subscription..."
  
  # Retreive the updated subscription
  subscription = body['data']['object']['subscription']
  subscription_id = subscription['id']
  plan_id = subscription['plan_id']
  
  url = URI("#{@square_url}/v2/subscriptions/#{subscription_id}")

  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true
  
  request = Net::HTTP::Get.new(url)
  request["Square-Version"] =  '2022-01-20'
  request["Accept"] = 'application/json'
  request["Authorization"] = @square_api_key
  
  response = http.request(request)
  
  sub_body = JSON.parse(response.read_body)
  
  if subscription['canceled_date']
    canceled = subscription['canceled_date']
    canceled_at = Date.parse(canceled)
    
    url = URI("https://api.baremetrics.com/v1/#{@bm_source_id}/subscriptions/#{subscription_id}/cancel")

    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    
    request = Net::HTTP::Put.new(url)
    request["Accept"] = 'application/json'
    request["Content-Type"] = 'application/json'
    request["Authorization"] = @bm_key
    request.body = "{\"canceled_at\":\"#{canceled_at.to_time.to_i}\"}"
    
    response = http.request(request)
    puts response.read_body

    if response.is_a?(Net::HTTPOK)
      puts "Subscription canceled!"
    else
      puts "Something Wrong..."
    end
  else
    # If it doesnt exist, create it.
    url = URI("https://api.baremetrics.com/v1/#{@bm_source_id}/subscriptions/#{subscription_id}")
  
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    
    request = Net::HTTP::Put.new(url)
    request["Accept"] = 'application/json'
    request["Content-Type"] = 'application/json'
    request["Authorization"] = @bm_key
    request.body = "{\"occurred_at\":\"NOW\",\"quantity\":1,\"plan_oid\":\"#{plan_id}\"}"
    
    response = http.request(request)

    if response.is_a?(Net::HTTPOK)
      puts response.read_body
    elsif response.is_a?(Net::HTTPNotFound)
      puts "Not found. Create subscription..."
      subscription_created(body)
    else
      puts "Something Wrong..."
    end
  end
end

def deleted_subscription(id)
  puts "Deleting subscription..."

  url = URI("https://api.baremetrics.com/v1/#{@bm_source_id}/subscriptions/#{id}")

  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true

  request = Net::HTTP::Delete.new(url)
  request["Accept"] = 'application/json'
  request["Authorization"] = @bm_key

  response = http.request(request)
  puts response.read_body
  puts response
  if response.is_a?(Net::HTTPAccepted)
    puts "Subscription deleted!"
  else
    puts "Something Wrong..."
  end
end