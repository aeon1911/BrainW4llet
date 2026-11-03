// Formatação de valores e datas (mesmas regras de lib/presentation/widgets/format.dart).

export function formatUnits(value, decimals) {
  const v = BigInt(value);
  const negative = v < 0n;
  const digits = (negative ? -v : v).toString().padStart(decimals + 1, '0');
  const whole = digits.slice(0, digits.length - decimals);
  const fraction = digits.slice(digits.length - decimals).replace(/0+$/, '');
  const text = fraction ? `${whole}.${fraction}` : whole;
  return negative ? `-${text}` : text;
}

export function formatSigned(value, decimals, ticker) {
  const v = BigInt(value);
  const text = formatUnits(v < 0n ? -v : v, decimals);
  return `${v < 0n ? '−' : '+'}${text} ${ticker}`;
}

export function formatDate(ms) {
  if (ms == null) return 'pendente';
  const t = new Date(ms);
  const two = (n) => String(n).padStart(2, '0');
  return `${two(t.getDate())}/${two(t.getMonth() + 1)}/${t.getFullYear()} ${two(t.getHours())}:${two(t.getMinutes())}`;
}

export function formatAgo(ms) {
  const minutes = Math.floor((Date.now() - ms) / 60000);
  if (minutes < 1) return 'agora';
  if (minutes < 60) return `há ${minutes} min`;
  const hours = Math.floor(minutes / 60);
  return hours < 24 ? `há ${hours} h` : formatDate(ms);
}

export function shorten(text, keep = 8) {
  return text.length <= keep * 2 + 1 ? text : `${text.slice(0, keep)}…${text.slice(-keep)}`;
}
