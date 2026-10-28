# Lex strings/comments/punctuation, then let fromJSON validate the JSON grammar.
# JSONC comments are not nested, so recognizing them needs no recursive parser.
text:
let
  string = ''"([^"\\]|\\.)*"'';
  lineComment = "//[^\r\n]*";
  blockComment = ''/\*([^*]|\*+[^*/])*\*+/'';
  whitespace = "[ \t\r\n]+";
  punctuation = "[][{},:]";
  pieces = builtins.split "(${string}|${lineComment}|${blockComment}|${whitespace}|${punctuation})" text;
  isWhitespace = token: builtins.match whitespace token != null;
  isComment = token: builtins.substring 0 2 token == "//" || builtins.substring 0 2 token == "/*";
  tokens = builtins.filter (token: token != "" && !isWhitespace token && !isComment token) (
    map (
      piece:
      if builtins.isList piece then
        builtins.head piece
      # Unmatched quotes or slashes mean a malformed string/comment. Do not
      # silently interpret comment markers inside an unterminated string.
      else if builtins.match ''[^"/]*'' piece == null then
        throw "Invalid JSONC string or comment"
      else
        piece
    ) pieces
  );
  count = builtins.length tokens;
  normalized = builtins.genList (
    index:
    let
      token = builtins.elemAt tokens index;
      previous = if index == 0 then "" else builtins.elemAt tokens (index - 1);
      next = if index + 1 == count then "" else builtins.elemAt tokens (index + 1);
      trailing =
        token == ","
        && builtins.elem next [
          "}"
          "]"
        ]
        && index > 0
        && !builtins.elem previous [
          "{"
          "["
          ","
          ":"
        ];
    in
    if trailing then "" else token
  ) count;
in
# Spaces prevent removal of comments from joining tokens (1/*x*/2 -> 12).
builtins.fromJSON (builtins.concatStringsSep " " normalized)
