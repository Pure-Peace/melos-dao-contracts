import { create, all } from 'mathjs';
const mathjs: math.MathJsStatic = create(all) as any;
mathjs.config({
  number: 'BigNumber',      // Default type of number:
  // 'number' (default), 'BigNumber', or 'Fraction'
  precision: 78             // Number of significant digits for BigNumbers
});
function ms(values: any, ...keys: any): string {
  const parts: string[] = [values[0] || ""];

  for (let i = 1, l = values.length; i < l; i++) {
    parts.push(keys[i - 1] + "");
    parts.push(values[i] + "");
  }
  return mathjs.evaluate(parts.join("")).toFixed(0);
}


export {
  ms,
  ms as mstr
}
