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
         
  if !event['body'].nil?
    body = JSON.parse(event['body'])
    puts body
    puts body['type']

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
  
  { statusCode: 200, body: JSON.generate('Ok') }
end

def customer_created(body)
  customer = body['data']['object']['customer']
  name = "#{customer['given_name']} #{customer['family_name']}"
  email = customer['email_address']
  oid = customer['id']
  created = customer['created_at']
  created_at = Date.parse(created)
  
  puts "Creating"
  url = URI("https://api.baremetrics.com/v1/82145757-9f4b-46e3-b67b-0bbf8632d0dd/customers")
  
  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true
  
  request = Net::HTTP::Post.new(url)
  request["Accept"] = 'application/json'
  request["Content-Type"] = 'application/json'
  request["Authorization"] = @bm_key
  request.body = "{\"created\":\"#{created_at.to_time.to_i}\",\"oid\":\"#{oid}\",\"name\":\"#{name}\",\"email\":\"#{email}\"}"
  
  response = http.request(request)
  puts response.read_body
  puts "I am created"
end

def customer_updated(body)
  customer = body['data']['object']['customer']
  name = "#{customer['given_name']} #{customer['family_name']}"
  email = customer['email_address']
  oid = customer['id']
  created = customer['created_at']
  created_at = Date.parse(created)
  
  puts "Updating..."
  
  url = URI("https://api.baremetrics.com/v1/82145757-9f4b-46e3-b67b-0bbf8632d0dd/customers/#{oid}")

  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true
  
  request = Net::HTTP::Put.new(url)
  request["Accept"] = 'application/json'
  request["Content-Type"] = 'application/json'
  request["Authorization"] = @bm_key
  request.body = "{\"name\":\"#{name}\",\"email\":\"#{email}\",\"created\":\"#{created_at.to_time.to_i}\"}"

  response = http.request(request)
  puts response.read_body

  if response.is_a?(Net::HTTPNotFound)
    customer_created(body)
  end
end

def customer_deleted(body)
  customer = body['data']['object']['customer']
  oid = customer['id']
  
  puts "Deleting..."
  url = URI("https://api.baremetrics.com/v1/82145757-9f4b-46e3-b67b-0bbf8632d0dd/customers/#{oid}")

  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true
  
  request = Net::HTTP::Delete.new(url)
  request["Accept"] = 'application/json'
  request["Authorization"] = @bm_key
  
  response = http.request(request)
  puts response.read_body
  puts " I was deleted"
end

def catalog_version_updated
  
  puts "Catalog Version Updated"
  
  bm_plans_id_list
  puts @bm_plan_ids
  
  # List Square Plans
  url = URI("https://connect.squareupsandbox.com/v2/catalog/list")

  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true
  
  request = Net::HTTP::Get.new(url)
  request["Square-Version"] =  '2022-01-20'
  request["Accept"] = 'application/json'
  request["Authorization"] = @square_api_key
  
  response = http.request(request)
  puts "Body:: #{response.read_body}"
  body = JSON.parse(response.read_body)
  
  puts body['objects'].count
  
  body['objects'].each do |value|
    
    puts value['id']
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
        
        #puts "Trial duration:: #{trial_periods}"
        #puts "Trial duration unit:: #{trial_cadence}"
        
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
        when "MONTHLY"
            interval = "month"
            interval_count = 1
        when "WEEKLY"
            interval = 'day'
            interval_count = 7
        when "ANNUAL"
            interval = 'year'
            interval_count = 1
        end
      end
    end
    
    puts @bm_plan_ids.include?(plan_oid)
    
    if !@bm_plan_ids.include?(plan_oid)
      #plan doesnt exists
      puts "plan_name:: #{plan_name}"
      puts "plan_oid:: #{plan_oid}"
      puts "Amount:: #{amount}"
      puts "Currency:: #{currency}"
      puts "Interval:: #{interval}"
      puts "Interval count:: #{interval_count}"
      puts "trial_duration:: #{trial_duration}"
      #puts "Is blank:: #{trial_duration.zero? || trial_duration.nil}"
      puts "trial_duration_unit:: #{trial_duration_unit}"
      
      
      puts "plan_name:: #{plan_name} Started!"
      url = URI("https://api.baremetrics.com/v1/82145757-9f4b-46e3-b67b-0bbf8632d0dd/plans")

      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true
      puts "plan_name:: #{plan_name} Started2!"
      request = Net::HTTP::Post.new(url)
      request["Accept"] = 'application/json'
      request["Content-Type"] = 'application/json'
      request["Authorization"] = @bm_key
      
      if trial_duration.zero? || trial_duration.nil?
          puts "plan_name:: #{plan_name} 0!"
          request.body = "{\"oid\":\"#{plan_oid}\",\"name\":\"#{plan_name}\",\"currency\":\"#{currency}\",\"amount\":#{amount},\"interval\":\"#{interval}\",\"interval_count\":#{interval_count}}"
      else
          puts "plan_name:: #{plan_name} 1!"
          request.body = "{\"trial_duration\":#{trial_duration},\"trial_duration_unit\":\"day\",\"oid\":\"#{plan_oid}\",\"name\":\"#{plan_name}\",\"currency\":\"#{currency}\",\"amount\":#{amount},\"interval\":\"#{interval}\",\"interval_count\":#{interval_count}}"
      end
      
      puts "plan_name:: #{plan_name} Started3!"
      puts "Request:: #{request}"
      response = http.request(request)
      puts "Body response1:: #{response}"
      puts "Body response:: #{response.read_body.force_encoding("utf-8")}"
    else
      bm_plan = @bm_plans_list.find {|key| key['oid'] == plan_oid}
      
      puts bm_plan.class
      puts bm_plan['name']
      
      if plan_name != bm_plan['name']
        puts "name not equal"
        url = URI("https://api.baremetrics.com/v1/82145757-9f4b-46e3-b67b-0bbf8632d0dd/plans/#{plan_oid}")

        http = Net::HTTP.new(url.host, url.port)
        http.use_ssl = true
        
        request = Net::HTTP::Put.new(url)
        request["Accept"] = 'application/json'
        request["Content-Type"] = 'application/json'
        request["Authorization"] = @bm_key
        request.body = "{\"name\":\"#{plan_name}\"}"
        
        response = http.request(request)
        puts response.read_body
        puts "plan name updated"
      else
        puts "name equal"
      end
    end
  end
end

def bm_plans_id_list
  @bm_plan_ids = []
  @bm_plans_hash = {}
  
  url = URI("https://api.baremetrics.com/v1/82145757-9f4b-46e3-b67b-0bbf8632d0dd/plans")

  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true
  
  request = Net::HTTP::Get.new(url)
  request["Accept"] = 'application/json'
  request["Authorization"] = @bm_key
  
  response = http.request(request)
  #puts "BM Plans list response:: #{response.read_body.force_encoding('UTF-8')}"
  
  body = JSON.parse(response.read_body)
  #puts "BM Plans list body:: #{body}"
  body['plans'].each do |plan|
    @bm_plan_ids << plan['oid']
  end
  
  @bm_plans_list = body['plans']
  @bm_plan_ids
end

def subscription_created(body)
  puts "Subscription Created"
  
  puts subscription = body['data']['object']['subscription']
  puts subscription['id']
  
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
  
  puts "Oid:: #{oid}"
  puts "PlanOid:: #{plan_oid}"
  puts "CustomerOid:: #{customer_oid}"
  puts "StartedDate:: #{started_date}"
  puts "STatus:: #{active}"
  
  url = URI("https://api.baremetrics.com/v1/82145757-9f4b-46e3-b67b-0bbf8632d0dd/subscriptions")

  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true
  
  request = Net::HTTP::Post.new(url)
  request["Accept"] = 'application/json'
  request["Content-Type"] = 'application/json'
  request["Authorization"] = @bm_key
  request.body = "{\"quantity\":1,\"oid\":\"#{oid}\",\"started_at\":\"#{started_date.to_time.to_i}\",\"plan_oid\":\"#{plan_oid}\",\"customer_oid\":\"#{customer_oid}\"}"
  
  response = http.request(request)
  puts response.read_body
end

def subscription_updated(body)
  puts "I was updated!"
  
  # Retreive the updated subscription
  subscription = body['data']['object']['subscription']
  subscription_id = subscription['id']
  plan_id = subscription['plan_id']
  
  puts "Subscription id:: #{subscription_id}"
  puts "Plan id:: #{plan_id}"
  
  url = URI("https://connect.squareupsandbox.com/v2/subscriptions/#{subscription_id}")

  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true
  
  request = Net::HTTP::Get.new(url)
  request["Square-Version"] =  '2022-01-20'
  request["Accept"] = 'application/json'
  request["Authorization"] = @square_api_key
  
  response = http.request(request)
  puts response.read_body
  
  sub_body = JSON.parse(response.read_body)
  puts "SubsInfo #{sub_body['subscription']}"
  puts "SubsCanceled #{subscription['canceled_date']}"
  
  if subscription['canceled_date']
    canceled = subscription['canceled_date']
    canceled_at = Date.parse(canceled)
    puts "Subscription canceled:: #{canceled_at.to_time.to_i}"
    
    url = URI("https://api.baremetrics.com/v1/82145757-9f4b-46e3-b67b-0bbf8632d0dd/subscriptions/#{subscription_id}/cancel")

    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    
    request = Net::HTTP::Put.new(url)
    request["Accept"] = 'application/json'
    request["Content-Type"] = 'application/json'
    request["Authorization"] = @bm_key
    request.body = "{\"canceled_at\":\"#{canceled_at.to_time.to_i}\"}"
    
    response = http.request(request)
    puts response.read_body
  else
    # Get the data and sent it to BM
    url = URI("https://api.baremetrics.com/v1/82145757-9f4b-46e3-b67b-0bbf8632d0dd/subscriptions/#{subscription_id}")
  
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    
    request = Net::HTTP::Put.new(url)
    request["Accept"] = 'application/json'
    request["Content-Type"] = 'application/json'
    request["Authorization"] = @bm_key
    request.body = "{\"occurred_at\":\"NOW\",\"quantity\":1,\"plan_oid\":\"#{plan_id}\"}"
    
    response = http.request(request)
    
    puts response.code
    puts response.code.class
    
    if response.code == "404"
      puts "not found!!!!!!!"
      subscription_created(body)
    else
      puts "found"
      puts response.read_body
    end
  end
end
