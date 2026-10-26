import isOdd from 'is-odd';
import isNumber from 'is-number';
export const message = isNumber(3) && isOdd(3) ? 'catalogs work' : 'broken';
