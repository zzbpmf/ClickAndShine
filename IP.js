if ($response.statusCode !== 200) {
  $done(null);
}

let obj = JSON.parse($response.body);

// IP
let ip = obj['query'];

// 把标题改成 IP
let title = ip;

// 副标题你随便排，我这里示例国家 + 城市 + 运营商
let subtitle = obj['country'] + ' ' + obj['city'] + ' ' + obj['isp'];

// 详情
let description =
  'IP: ' + ip + '\n' +
  '国家: ' + obj['country'] + '\n' +
  '城市: ' + obj['city'] + '\n' +
  '运营商: ' + obj['isp'] + '\n' +
  '数据中心: ' + obj['org'];

$done({ title, subtitle, ip, description });
