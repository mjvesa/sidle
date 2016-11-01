(*
 * Sidle - Shoplifter IDE, cunning Pascal 320x200 version
 *
 *)
program Sidle;

const 
  CURSOR : array [1..4, 1..4] of byte = ((15, 15, 15,  0),
                                        (15, 15,  0,  0),
                                        (15,  0, 15,  0),
                                        ( 0,  0,  0, 15));

  CODE_START      = 1024;
  MAX_WORD_COUNT  = 100;
  DSTACKDEPTH     = 100;
  RSTACKDEPTH     = 100;
  BLOCK_SIZE      = 1024; {Standard 64x16 block}



type 
  Instruction = (_LIT, _MUL,_DIV,_ADD,_SUB, _STORE, _LOAD, _DUP, _SWAP,
                 _DROP, _EXECUTE,_PRINT, _DEF, _RET, _PIXEL, _FLIP);

  Vscr   = array [0..63999] of byte;
  PVscr  = ^Vscr;
  DaHeap = array [0..32766] of integer;
  PHeap  = ^DaHeap;

var 
  font           : array [0..127, 0..31] of byte;
  mouseX, mouseY,
  mouseB         : integer;
  virt           : PVscr;
  cursorCol,
  cursorRow      : integer;

  inputIndex     : integer;
  words          : array [0..MAX_WORD_COUNT] of String;
  wordOffsets    : array [0..MAX_WORD_COUNT] of integer;
  dataStack      : array [0..DSTACKDEPTH] of integer;
  returnStack    : array [0..RSTACKDEPTH] of integer;
  heap           : PHeap;
  dstackTop      : integer;
  rstackTop      : integer;
  wordCount      : integer;
  heapIndex      : integer;
  ip             : integer;

procedure Font4x8;
external;
{$L font4x8.obj}

(*
 *   Draws a rectangle with a border. Flat colors.
 *)
procedure DrawRect(x1, y1, x2, y2 : integer ; border, background : byte);

var 
  x, y   : integer;
  color  : byte;
begin
  for y := y1 to y2 Do
    begin
      for x := x1 to x2 Do
        begin
          if (x = x1) or (x = x2) or (y = y1) or (y = y2) then begin
                                                                 color := border;
            end{if}
          else begin
                 color := background;
            end{else};
          virt^[y * 320 + x] := color;
        end;
    end;
end;

procedure GetMouse;
begin
  asm
  mov ax, 3
  int 33h
  shr cx, 1
  mov mouseX, cx
  mov mouseY, dx
  mov mouseB, bx
end;
end;

procedure Flip;

var 
  i : word;
begin
  for i := 0 to 63999 Do
    begin
      mem[$a000: i] := virt^[i];
    end;
end;

procedure Cls;

var 
  i : word;
begin
  for i := 0 to 63999 Do
    begin
      virt^[i] := i;
    end;
end;

procedure Pixel(x, y : integer; color : byte);
begin
  virt^[y * 320 + x] := color;
end;


procedure DrawMouseCursor;

var 
  i, j : integer;
begin
  for i := 1 to 4 Do
    begin
      for j := 1 to 4 Do
        begin
          if (cursor[i, j] > 0) then begin
                                       pixel(mouseX + j - 1, mouseY + i - 1, cursor[i, j]);
            end;
        end;
    end;
end;

procedure DrawTextCursor;

var 
  sx, sy, x, y : integer;
begin
  sx := cursorCol * 4 + 11;
  sy := cursorRow * 8 + 1;

  for y := 0 to 7 Do
    begin
      for x := 0 to 3 Do
        begin
          pixel(sx + x, sy + y, 5);
        end;
    end;
end;

procedure GrabFont;

var
  i, j, x, y, index  : integer;
  fontseg, fontofs   : word;
  c                  : byte;
begin
  fontseg := seg(Font4x8);
  fontofs := ofs(Font4x8);
  for i := 32 to 127 Do
    begin
      index := ((i - 32) Div 32) * 128 * 8 + (i And 31) * 4;
      for y := 0 to 7 Do
        begin
          for x := 0 to 3 Do
            begin
              font[i, y * 4 + x] := 
                                    mem[fontseg: fontofs + index + y * 128 + x];
            end;
        end;
    end;
end;

procedure DrawChar(ch : char; sx, sy : integer);

var 
  x, y : integer;
begin
  for y := 0 to 7 Do
    begin
      for x := 0 to 3 Do
        begin
          if (font[ord(ch),
             x + y * 4] = 0) then begin
                                    virt^[sx + x + (sy + y) * 320] := 15;
            end;
        end;
    end;
end;

procedure DrawString(text : String; sx, sy : integer);

var 
  i : integer;
begin
  for i := 1 to length(text) Do
    begin
      drawChar(text[i], sx + (i - 1) * 4, sy);
    end;
end;

procedure PrintCode;

var 
  i, j : integer;
begin
  for i := 0 to 15 Do
    begin
      for j := 0 to 63 Do
        begin
          DrawChar(chr(heap^[i * 64 + j]), 11 + j * 4, 1 + i * 8);
        end;
    end;
end;

procedure DrawLineNumbers;

var 
  i : integer;
  s : string;
begin
  for i := 0 to 15 Do
    begin
      Str(i + 1, s);
      DrawString(s, 1, 1 + i * 8);
    end;
end;

procedure DrawCodeArea;
begin
  DrawRect(0, 0, 256 + 11, 129, 3, 1);
  DrawRect(0, 0, 10, 129, 3, 1);
  DrawLineNumbers;
end;

procedure EmitEnter;

var 
  i : integer;
begin
  for i := 0 to 63 - cursorCol Do
    begin
      heap^[i + (cursorRow  + 1) * 64] := heap^[cursorCol + i + cursorRow * 64];
      heap^[cursorCol + i + cursorRow * 64] := ord(' ');
    end;
  cursorCol := 0;
  cursorRow := (cursorRow + 1) And 15;
end;

procedure SetCodeAt(ch : char ; col, row : integer);
begin
  heap^[col + row * 64] := ord(ch);
end;

procedure EmitBackSpace;

var 
  i : integer;
begin
  for i := cursorCol to 63 Do
    begin
      heap^[i - 1 + cursorRow * 64] := heap^[i + cursorRow * 64];
    end;
  dec(cursorCol);
  heap^[15 + cursorRow * 64] := ord(' ');
end;

procedure ClearCode;

var 
  i : integer;
begin
  for i := 0 to 1023 Do
    begin
      heap^[i] := ord(' ');
    end;
end{proc};


{****************************************************************************
 *** Interpreter ************************************************************
 ****************************************************************************}
function hasNextWord: boolean;
begin
  hasNextWord :=  inputIndex < BLOCK_SIZE;
end;

function getNextWord: String;

var 
  str : String;
begin
  while (inputIndex < BLOCK_SIZE) and (heap^[inputIndex] = ord(' ')) Do
    begin
      inc(inputIndex,1);
    end;
  str := '';
  while (inputIndex < BLOCK_SIZE) and (heap^[inputIndex] <> ord(' ')) Do
    begin
      str := str + chr(heap^[inputIndex]);
      inc(inputIndex,1);
    end;
  getNextWord := str;
end;

procedure dataPush(a : integer);
begin
  dataStack[dstackTop] := a;
  inc(dstackTop);
end;

function dataPop: integer;
begin
  dec(dstackTop);
  dataPop := dataStack[dstackTop];
end;

procedure rPush(a : integer);
begin
  returnStack[rstackTop] := a;
  inc(rstackTop);
end;

function rPop: integer;
begin
  dec(rstackTop);
  rPop := returnStack[rstackTop];
end;


function tokenize(word : String): integer;

var 
  i       : integer;
  found   : boolean;
begin
  found := false;
  i := wordCount;
  while (i > 0)  and (found = false) Do
    begin
      dec(i, 1);
      if words[i] = word then begin
                                found := true;
        end;
    end;
  tokenize := i;
end;

function isInteger(str : String): boolean;

var 
  whut : boolean;
  i   : integer;
begin
  whut := true;
  for i := 1 to length(str) Do
    begin
      if (ord(str[i]) < 48) or (ord(str[i]) > 57) then begin
                                                         whut := false;
        end;
    end;
  isInteger := whut;
end;


function StrToInt(str : String): integer;

var 
  intValue, code : integer;
begin
  val(str, intValue, code);
  StrToInt := intValue;
end;


procedure compile;

var 
  name : string;
  i    : integer;
  inst : integer;
begin
  i := heapIndex;
  name := getNextWord;
  words[wordCount] := name;
  wordOffsets[wordCount] := i;
  name := getNextWord;
  DrawString(name, 0, 180);
  while (name <> ';') Do
    begin
      inst := tokenize(name);
        {Write literal generating functions if inst not found }
      if (inst > 0) then begin
                           heap^[i] := inst;
        end
      else begin
             if isInteger(name) then begin
                                       dataPush(strToInt(name));
                                       heap^[i] := ord(_LIT);
                                       heap^[i + 1] := strToInt(name);
                                       inc(i);
               end
             else begin
                    writeln('did not recognize ', name, ' at index ', inputIndex);
               end;
        end;
      inc(i);
      name := getNextWord;
    end;
  heap^[i] := ord(_RET);
  heapIndex := i + 1;
  inc(wordCount);
end;


procedure execute(inst : integer);

var 
  a, b : integer;
begin
  case inst of 
    ord(_LIT): begin
	               dataPush(heap^[ip + 1]);
                 inc(ip);
               end;
    ord(_MUL): begin
                 a := dataPop;
                 b := dataPop;
                 dataPush(b * a);
               end;
    ord(_DIV): begin
                 a := dataPop;
                 b := dataPop;
                 dataPush(b Div b);
               end;
    ord(_ADD): begin
                 a := dataPop;
                 b := dataPop;
                 dataPush(b + a);
               end;
    ord(_SUB): begin
                 a := dataPop;
                 b := dataPop;
                 dataPush(b - a);
               end;
    ord(_LOAD): begin
                  a := dataPop;
                  dataPush(heap^[a]);
                end;
    ord(_STORE): begin
                   a := dataPop;
                   heap^[a] := dataPop;
                 end;
    ord(_EXECUTE): begin {Get a character}
                   end;
    ord(_PRINT): begin
                   writeln(dataPop);
                 end;
    ord(_DEF): begin
                 compile;
               end;
    ord(_PIXEL): begin
(* todo *)
                 end;
    ord(_FLIP): begin
(* todo *)
                end;
    else begin
           writeln('What did you say?');
      end;
  end;
end;

procedure executeToken(inst : integer);
forward;

procedure executeComposite(inst : integer);

var 
  i : integer;
begin
  rPush(ip);
  ip := wordOffsets[inst];
  while (heap^[ip] <> ord(_RET)) Do
    begin
      i := heap^[ip];
      executeToken(i);
      inc(ip);
    end;
  ip := rPop;
end;

procedure executeToken(inst : integer);
begin
  if (inst > ord(_RET)) then begin
                               executeComposite(inst);
    end
  else begin
         execute(inst);
    end;
end;

procedure Interpret;

var 
  inst : integer;
  str  : string;
begin
  inputIndex := 0;
  while hasNextWord Do
    begin
      str := getNextWord;
      inst := tokenize(str);
      if (inst > 0)  then begin
                            executeToken(inst);
        end
      else begin
             if isInteger(str) then begin
                                      dataPush(strToInt(str));
               end
             else begin
                    writeln('unrecognizable crap!');
               end;
        end;
    end;
end;

procedure FillWords;
begin
  words[ord(_LIT)] := 'LITERAL';
  words[ord(_MUL)] := '*';
  words[ord(_DIV)] := '/';
  words[ord(_ADD)] := '+';
  words[ord(_SUB)] := '-';
  words[ord(_STORE)] := '!';
  words[ord(_LOAD)] := '@';
  words[ord(_EXECUTE)] := 'execute';
  words[ord(_PRINT)] := 'print';
  words[ord(_DEF)] := ':';
  words[ord(_RET)] := ';';
  wordCount := ord(_RET) + 1;
  heapIndex := CODE_START;
  rstackTop := 0;
  dstackTop := 0;
end;

function keypressed:boolean;
var
	value : byte;
begin
  value:=0;
	asm
  	mov ah,1
    int 16h
    jz @@notpressed
    mov value, 1
@@notpressed:
  end;
	keypressed:=value=1;
end;

function readkey:char;
var
 	result : char;
begin
	asm
  	xor ax,ax
    int 16h
    mov result,al
  end;
  readkey:=result;
end;

procedure HandleKeys;
var
  ch : char;
begin
  if keypressed then begin
		ch := readkey;
    if (ch = #0) then begin
    	ch := readkey;
			case (ch) of
      	#$0e: begin
        	cursorCol := (cursorCol - 1) And 63
        end;
                                             #$50: begin
                                                     cursorRow := (cursorRow + 1) And 15
                                                   end;
                                             #$48: begin
                                                     cursorRow := (cursorRow - 1) And 15
                                                   end;
                                             #$4d: begin
                                                     cursorCol := (cursorCol + 1) And 63
                                                   end;
                                             #$4b: begin
                                                     cursorCol := (cursorCol - 1) And 63
                                                   end;
                                             #$43: begin
                                                     interpret;
                                                   end;
                                           end;
                         end
                       else begin
                              case (ch) of
                                #$0d: EmitEnter;
                                #$08: EmitBackSpace;
                                else begin
                                       heap^[cursorCol + cursorRow * 64] := ord(ch);
                                       inc(cursorCol);
                                  end;
 	                            end;
                         end;
    end;
end;

begin
  FillWords;
  new(virt);
  new(heap);

  asm
  	mov ax, 13h
	  int 10h
	end;

	GrabFont;
	Cls;
	ClearCode;
	DrawRect(0, 0, 319, 199, 3 ,1);

	repeat
	  HandleKeys;
	  GetMouse;
	  DrawCodeArea;
	  PrintCode;
	  DrawMouseCursor;
	  DrawTextCursor;
	  Flip;
	until port[$60] = 1;

	asm
		mov ax, 3h
		int 10h
	end;
	dispose(virt);
	dispose(heap);
end.
