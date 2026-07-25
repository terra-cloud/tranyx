export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
          "Access-Control-Allow-Headers": "*",
          "Access-Control-Max-Age": "86400",
        },
      });
    }

    try {
      const url = "https://api.cloudflare.com/client/v4/accounts/b4f055485eaa21f69478310436ef91cf/ai/run/@cf/meta/llama-3.2-3b-instruct";
      const body = await request.text();

      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Authorization": "Bearer cfut_TFIoZl6cJjkqL1zni7NQfFmWAVOcOTl1hzs9fqen6b356cfe",
          "Content-Type": "application/json",
        },
        body: body,
      });

      const resBody = await response.text();
      return new Response(resBody, {
        status: response.status,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Content-Type": "application/json",
        },
      });
    } catch (e) {
      return new Response(JSON.stringify({ error: e.toString() }), {
        status: 500,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Content-Type": "application/json",
        },
      });
    }
  }
};
