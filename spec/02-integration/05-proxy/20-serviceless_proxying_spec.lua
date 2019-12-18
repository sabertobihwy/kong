local http_request = require "http.request"
local http_tls = require "http.tls"
local openssl_ssl = require "openssl.ssl"
local helpers = require "spec.helpers"
local cjson = require "cjson"
local meta = require "kong.meta"


local tonumber = tonumber
local null = ngx.null


local HTTP_PROXY_HOST = helpers.get_proxy_ip(false)
local HTTP_PROXY_PORT = helpers.get_proxy_port(false)
local HTTPS_PROXY_HOST = helpers.get_proxy_ip(true)
local HTTPS_PROXY_PORT = helpers.get_proxy_port(true)
local HTTP_PROXY_URI  = "http://"  .. HTTP_PROXY_HOST .. ":" .. HTTP_PROXY_PORT
--local HTTPS_PROXY_URI = "https://" .. HTTPS_PROXY_HOST  .. ":" .. HTTPS_PROXY_PORT
local HTTP_UPSTREAM_URI = helpers.mock_upstream_url .. "/anything"
local HTTPS_UPSTREAM_URI = helpers.mock_upstream_ssl_url .. "/anything"
local HTTP_UPSTREAM_HOST = helpers.mock_upstream_host .. ":" .. helpers.mock_upstream_port
local HTTPS_UPSTREAM_HOST = helpers.mock_upstream_host .. ":" .. helpers.mock_upstream_ssl_port


for _, strategy in helpers.each_strategy() do
  describe("Serviceless Proxying [#" .. strategy .. "]", function()
    describe("[http]", function()
      lazy_setup(function()
        local bp = helpers.get_db_utils(strategy, {
          "routes",
        })

        bp.routes:insert {
          paths   = { "/" },
          service = null,
        }

        assert(helpers.start_kong({
          database      = strategy,
          nginx_conf    = "spec/fixtures/custom_nginx.template",
          stream_listen = "off",
          admin_listen  = "off",
        }))
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("proxies http to http (request-line)", function()
        local request = http_request.new_from_uri(HTTP_UPSTREAM_URI)
        request.proxy = HTTP_PROXY_URI
        request.version = 1.1
        request.tls = false
        local headers, stream = request:go()

        assert.equal(200, tonumber((headers:get(":status"))))
        assert.equal(meta._SERVER_TOKENS, (headers:get("via")))

        local body = assert(stream:get_body_as_string())
        local json = cjson.decode(body)

        assert.equal(HTTP_PROXY_PORT, tonumber(json.headers["x-forwarded-port"]))
        assert.equal("http", json.headers["x-forwarded-proto"])

        stream:shutdown()
      end)

      it("proxies https to http (request-line)", function()
        local ctx = http_tls.new_client_context()
        ctx:setVerify(openssl_ssl.VERIFY_NONE)

        local request = http_request.new_from_uri(HTTP_UPSTREAM_URI)
        request.headers:upsert(":path", request:to_uri(false))
        request.host = HTTPS_PROXY_HOST
        request.port = HTTPS_PROXY_PORT
        request.version = 1.1
        request.tls = true
        request.ctx = ctx
        local headers, stream = request:go()

        assert.equal(200, tonumber((headers:get(":status"))))
        assert.equal(meta._SERVER_TOKENS, (headers:get("via")))

        local body = assert(stream:get_body_as_string())
        local json = cjson.decode(body)

        assert.equal(HTTP_UPSTREAM_HOST, json.headers["host"])
        assert.equal(HTTPS_PROXY_PORT, tonumber(json.headers["x-forwarded-port"]))
        assert.equal("https", json.headers["x-forwarded-proto"])

        stream:shutdown()
      end)

      it("proxies http to http (host-header)", function()
        local request = http_request.new_from_uri(HTTP_UPSTREAM_URI)
        request.headers:upsert(":path", "/anything")
        request.headers:upsert("host", HTTP_UPSTREAM_HOST)
        request.host = HTTP_PROXY_HOST
        request.port = HTTP_PROXY_PORT
        request.version = 1.1
        request.tls = false
        local headers, stream = request:go()

        assert.equal(200, tonumber((headers:get(":status"))))
        assert.equal(meta._SERVER_TOKENS, (headers:get("via")))

        local body = assert(stream:get_body_as_string())
        local json = cjson.decode(body)

        assert.equal(HTTP_UPSTREAM_HOST, json.headers["host"])
        assert.equal(HTTP_PROXY_PORT, tonumber(json.headers["x-forwarded-port"]))
        assert.equal("http", json.headers["x-forwarded-proto"])

        stream:shutdown()
      end)

      -- TODO: needs https://github.com/chobits/ngx_http_proxy_connect_module
      pending("proxies http to https (connect)", function()
        local ctx = http_tls.new_client_context()
        ctx:setVerify(openssl_ssl.VERIFY_NONE)

        local request = http_request.new_from_uri(HTTPS_UPSTREAM_URI)
        request.proxy = HTTP_PROXY_URI
        request.version = 1.1
        request.tls = true
        request.ctx = ctx
        local headers, stream = request:go()

        assert.equal(200, tonumber((headers:get(":status"))))

        local body = assert(stream:get_body_as_string())
        local json = cjson.decode(body)

        assert.equal(HTTPS_UPSTREAM_HOST, json.headers["host"])

        stream:shutdown()
      end)

      -- TODO: needs https://github.com/chobits/ngx_http_proxy_connect_module
      pending("proxies https to https (connect)", function()
      end)
    end)

    describe("[http2]", function()
      lazy_setup(function()
        local bp = helpers.get_db_utils(strategy, {
          "routes",
        })

        bp.routes:insert {
          paths = { "/" },
          service = null,
        }

        assert(helpers.start_kong({
          proxy_listen  = HTTP_PROXY_HOST  .. ":" .. HTTP_PROXY_PORT  .. " http2, " ..
                          HTTPS_PROXY_HOST .. ":" .. HTTPS_PROXY_PORT .. " http2 ssl",
          database      = strategy,
          nginx_conf    = "spec/fixtures/custom_nginx.template",
          stream_listen = "off",
          admin_listen  = "off",
        }))

      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      -- TODO: nginx doesn't allow absolute uris in http2 path component
      pending("proxies http to http (request-line)", function()
        local request = http_request.new_from_uri(HTTP_UPSTREAM_URI)
        request.proxy = HTTP_PROXY_URI
        request.version = 2.0
        request.tls = false
        local headers, stream = request:go()

        assert.equal(200, tonumber((headers:get(":status"))))
        assert.equal(meta._SERVER_TOKENS, (headers:get("via")))

        local body = assert(stream:get_body_as_string())
        local json = cjson.decode(body)

        assert.equal(HTTP_UPSTREAM_HOST, json.headers["host"])
        assert.equal(HTTP_PROXY_PORT, tonumber(json.headers["x-forwarded-port"]))
        assert.equal("http", json.headers["x-forwarded-proto"])

        stream:shutdown()
      end)

      -- TODO: nginx doesn't allow absolute uris in http2 path component
      pending("proxies https to http (request-line)", function()
        local ctx = http_tls.new_client_context()
        ctx:setVerify(openssl_ssl.VERIFY_NONE)

        local request = http_request.new_from_uri(HTTP_UPSTREAM_URI)
        request.headers:upsert(":path", request:to_uri(false))
        request.host = helpers.get_proxy_ip(true)
        request.port = helpers.get_proxy_port(true)
        request.version = 2.0
        request.tls = true
        request.ctx = ctx
        local headers, stream = request:go()

        assert.equal(200, tonumber((headers:get(":status"))))
        assert.equal(meta._SERVER_TOKENS, (headers:get("via")))

        local body = assert(stream:get_body_as_string())
        local json = cjson.decode(body)

        assert.equal(HTTP_UPSTREAM_HOST, json.headers["host"])
        assert.equal(HTTPS_PROXY_PORT, tonumber(json.headers["x-forwarded-port"]))
        assert.equal("https", json.headers["x-forwarded-proto"])

        stream:shutdown()
      end)

      it("proxies http to http (host-header)", function()
        local request = http_request.new_from_uri(HTTP_UPSTREAM_URI)
        request.headers:upsert(":path", "/anything")
        request.headers:upsert("host", HTTP_UPSTREAM_HOST)
        request.host = HTTP_PROXY_HOST
        request.port = HTTP_PROXY_PORT
        request.version = 2.0
        request.tls = false
        local headers, stream = request:go()

        assert.equal(200, tonumber((headers:get(":status"))))
        assert.equal(meta._SERVER_TOKENS, (headers:get("via")))

        local body = assert(stream:get_body_as_string())
        local json = cjson.decode(body)

        assert.equal(HTTP_UPSTREAM_HOST, json.headers["host"])
        assert.equal(HTTP_PROXY_PORT, tonumber(json.headers["x-forwarded-port"]))
        assert.equal("http", json.headers["x-forwarded-proto"])

        stream:shutdown()
      end)

      -- TODO: needs https://github.com/chobits/ngx_http_proxy_connect_module
      pending("proxies http to https (connect)", function()
        local ctx = http_tls.new_client_context()
        ctx:setVerify(openssl_ssl.VERIFY_NONE)

        local request = http_request.new_from_uri(HTTPS_UPSTREAM_URI)
        request.headers:upsert(":path", "/anything")
        request.headers:upsert(":authority", HTTPS_UPSTREAM_HOST)
        request.host = HTTP_PROXY_HOST
        request.port = HTTP_PROXY_PORT
        request.version = 2.0
        request.tls = true
        request.ctx = ctx
        local headers, stream = request:go()

        print(stream)
        assert.equal(200, tonumber((headers:get(":status"))))

        local body = assert(stream:get_body_as_string())
        local json = cjson.decode(body)

        assert.equal(HTTPS_UPSTREAM_HOST, json.headers["host"])

        stream:shutdown()
      end)
    end)
  end)
end