#!/usr/bin/env bun
import isOdd from "is-odd";
console.log(isOdd(Number(process.argv[2])) ? "odd" : "even");
