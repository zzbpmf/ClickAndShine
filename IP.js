if ($response.statusCode !== 200) {
  $done(null);
}

try {
  const obj = JSON.parse($response.body || "{}");

  const country = obj.country || "Unknown Country";
  const city    = obj.city    || "Unknown City";
  const isp     = obj.isp     || "Unknown ISP";
  const org     = obj.org     || "Unknown Org";
  const ip      = obj.query   || "Unknown IP";

  // 🔥 IP 放在最前面（主标题）
  const title = `${ip}`;

  // 第二行显示国家 / 城市 / 运营商
  const subtitle = `${country} · ${city} · ${isp}`;

  const description =
    `IP：${ip}\n` +
    `国家：${country}\n` +
    `城市：${city}\n` +
    `运营商：${isp}\n` +
    `数据中心：${org}`;

  $done({
    title,
    subtitle,
    description
  });

} catch (e) {
  $done(null);
}
