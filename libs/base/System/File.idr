module System.File

import Data.List
import Data.Strings
import System.Info

public export
data Mode = Read | WriteTruncate | Append | ReadWrite | ReadWriteTruncate | ReadAppend

public export
FilePtr : Type
FilePtr = AnyPtr

support : String -> String
support fn = "C:" ++ fn ++ ", libidris2_support"

libc : String -> String
libc fn = "C:" ++ fn ++ ", libc 6"

js_try_catch_lasterr_Int : String -> String
js_try_catch_lasterr_Int x = "{try{" ++ x ++ ";return 0n}catch(e){process.__lasterr = e; return 1n}}"

js_try_catch_lasterr_Ptr : String -> String
js_try_catch_lasterr_Ptr x = "{try{" ++ x ++ "}catch(e){process.__lasterr = e; return null}}"

js_open_file : String
js_open_file = "return {fd:__require_fs.openSync(n, m), buffer: Buffer.alloc(0), name:n, eof: false}"

%foreign support "idris2_openFile"
         ("node:lambdaRequire:fs:(n, m) =>" ++ js_try_catch_lasterr_Ptr js_open_file)
prim__open : String -> String -> Int -> PrimIO FilePtr

%foreign support "idris2_closeFile"
         ("node:lambdaRequire:fs:(fp) => __require_fs.closeSync(fp.fd)")
prim__close : FilePtr -> PrimIO ()

%foreign support "idris2_fileError"
         "node:lambda:x=>(x===1n?BigInt(1):BigInt(0))"
prim_error : FilePtr -> PrimIO Int

%foreign support "idris2_fileErrno"
         "node:lambda:()=>-BigInt(process._lasterr.errno)"
prim_fileErrno : PrimIO Int


read_line_js : String
read_line_js =
   "(file_ptr =>{
     const LF = 0x0a;
     const readBuf = Buffer.alloc(1);
     let lineEnd = file_ptr.buffer.indexOf(LF);
     while (lineEnd === -1) {
      const bytesRead = __require_fs.readSync(file_ptr.fd, readBuf);
      if (bytesRead === 0) {
       file_ptr.eof = true;
       break;
      }
      file_ptr.buffer = Buffer.concat([file_ptr.buffer, readBuf.slice(0, bytesRead)]);
      lineEnd = file_ptr.buffer.indexOf(LF);
     }
     const line = file_ptr.buffer.slice(0, lineEnd + 1);
     file_ptr.buffer = file_ptr.buffer.slice(lineEnd + 1);
     return line.toString('utf-8');
   })"

%foreign support "idris2_readLine"
         ("node:lambda:" ++ read_line_js)
prim__readLine : FilePtr -> PrimIO (Ptr String)

%foreign support "idris2_readChars"
prim__readChars : Int -> FilePtr -> PrimIO (Ptr String)
%foreign support "fgetc"
prim__readChar : FilePtr -> PrimIO Int

%foreign support "idris2_writeLine"
         "node:lambdaRequire:fs:(file_ptr, line) => __require_fs.writeSync(filePtr.fd, line, undefined, 'utf-8')"
prim__writeLine : FilePtr -> String -> PrimIO Int

%foreign support "idris2_eof"
         "node:lambda:x=>(x.eof?BigInt(1):BigInt(0))"
prim__eof : FilePtr -> PrimIO Int

%foreign "C:fflush,libc 6"
prim__flush : FilePtr -> PrimIO Int
%foreign support "idris2_popen"
prim__popen : String -> String -> PrimIO FilePtr
%foreign support "idris2_pclose"
prim__pclose : FilePtr -> PrimIO ()

%foreign support "idris2_removeFile"
prim__removeFile : String -> PrimIO Int

%foreign support "idris2_fileSize"
         "node:lambdaRequire:fs:fp=>__require_fs.fstatSync(fp.fd, {bigint: true}).size"
prim__fileSize : FilePtr -> PrimIO Int

%foreign support "idris2_fileSize"
prim__fPoll : FilePtr -> PrimIO Int

%foreign support "idris2_fileAccessTime"
prim__fileAccessTime : FilePtr -> PrimIO Int

%foreign support "idris2_fileModifiedTime"
         "node:lambdaRequire:fs:fp=>__require_fs.fstatSync(fp.fd, {bigint: true}).mtimeMs / 1000n"
prim__fileModifiedTime : FilePtr -> PrimIO Int

%foreign support "idris2_fileStatusTime"
prim__fileStatusTime : FilePtr -> PrimIO Int

%foreign support "idris2_stdin"
         "node:lambda:x=>({fd:0, buffer: Buffer.alloc(0), name:'<stdin>', eof: false})"
prim__stdin : FilePtr

%foreign support "idris2_stdout"
         "node:lambda:x=>({fd:1, buffer: Buffer.alloc(0), name:'<stdout>', eof: false})"
prim__stdout : FilePtr

%foreign support "idris2_stderr"
         "node:lambda:x=>({fd:2, buffer: Buffer.alloc(0), name:'<stderr>', eof: false})"
prim__stderr : FilePtr

%foreign libc "chmod"
         ("node:lambdaRequire:fs:(filename, mode) => " ++ js_try_catch_lasterr_Int "__require_fs.chmodSync(filename, Number(mode))")
prim__chmod : String -> Int -> PrimIO Int

modeStr : Mode -> String
modeStr Read              = if isWindows then "rb" else "r"
modeStr WriteTruncate     = if isWindows then "wb" else "w"
modeStr Append            = if isWindows then "ab" else "a"
modeStr ReadWrite         = if isWindows then "rb+" else "r+"
modeStr ReadWriteTruncate = if isWindows then "wb+" else "w+"
modeStr ReadAppend        = if isWindows then "ab+" else "a+"

public export
data FileError = GenericFileError Int -- errno
               | FileReadError
               | FileWriteError
               | FileNotFound
               | PermissionDenied
               | FileExists

returnError : IO (Either FileError a)
returnError
    = do err <- primIO prim_fileErrno
         case err of
              0 => pure $ Left FileReadError
              1 => pure $ Left FileWriteError
              2 => pure $ Left FileNotFound
              3 => pure $ Left PermissionDenied
              4 => pure $ Left FileExists
              _ => pure $ Left (GenericFileError (err-5))

export
Show FileError where
  show (GenericFileError errno) = "File error: " ++ show errno
  show FileReadError = "File Read Error"
  show FileWriteError = "File Write Error"
  show FileNotFound = "File Not Found"
  show PermissionDenied = "Permission Denied"
  show FileExists = "File Exists"

ok : a -> IO (Either FileError a)
ok x = pure (Right x)

public export
data File : Type where
     FHandle : FilePtr -> File

export
stdin : File
stdin = FHandle prim__stdin

export
stdout : File
stdout = FHandle prim__stdout

export
stderr : File
stderr = FHandle prim__stderr

export
openFile : String -> Mode -> IO (Either FileError File)
openFile f m
    = do res <- primIO (prim__open f (modeStr m) 0)
         if prim__nullAnyPtr res /= 0
            then returnError
            else ok (FHandle res)

export
closeFile : File -> IO ()
closeFile (FHandle f) = primIO (prim__close f)

export
fileError : File -> IO Bool
fileError (FHandle f)
    = do x <- primIO $ prim_error f
         pure (x /= 0)

export
fGetLine : (h : File) -> IO (Either FileError String)
fGetLine (FHandle f)
    = do res <- primIO (prim__readLine f)
         if prim__nullPtr res /= 0
            then returnError
            else ok (prim__getString res)

export
fGetChars : (h : File) -> Int -> IO (Either FileError String)
fGetChars (FHandle f) max
    = do res <- primIO (prim__readChars max f)
         if prim__nullPtr res /= 0
            then returnError
            else ok (prim__getString res)

export
fGetChar : (h : File) -> IO (Either FileError Char)
fGetChar (FHandle h)
    = do c <- primIO (prim__readChar h)
         ferr <- primIO (prim_error h)
         if (ferr /= 0)
            then returnError
            else ok (cast c)

export
fPutStr : (h : File) -> String -> IO (Either FileError ())
fPutStr (FHandle f) str
    = do res <- primIO (prim__writeLine f str)
         if res == 0
            then returnError
            else ok ()

export
fPutStrLn : (h : File) -> String -> IO (Either FileError ())
fPutStrLn f str = fPutStr f (str ++ "\n")

export
fEOF : (h : File) -> IO Bool
fEOF (FHandle f)
    = do res <- primIO (prim__eof f)
         pure (res /= 0)

export
fflush : (h : File) -> IO ()
fflush (FHandle f)
    = do primIO (prim__flush f)
         pure ()

export
popen : String -> Mode -> IO (Either FileError File)
popen f m = do
    ptr <- primIO (prim__popen f (modeStr m))
    if prim__nullAnyPtr ptr /= 0
        then returnError
        else pure (Right (FHandle ptr))

export
pclose : File -> IO ()
pclose (FHandle h) = primIO (prim__pclose h)

export
fileAccessTime : (h : File) -> IO (Either FileError Int)
fileAccessTime (FHandle f)
    = do res <- primIO (prim__fileAccessTime f)
         if res > 0
            then ok res
            else returnError

export
fileModifiedTime : (h : File) -> IO (Either FileError Int)
fileModifiedTime (FHandle f)
    = do res <- primIO (prim__fileModifiedTime f)
         if res > 0
            then ok res
            else returnError

export
fileStatusTime : (h : File) -> IO (Either FileError Int)
fileStatusTime (FHandle f)
    = do res <- primIO (prim__fileStatusTime f)
         if res > 0
            then ok res
            else returnError

export
removeFile : String -> IO (Either FileError ())
removeFile fname
    = do res <- primIO (prim__removeFile fname)
         if res == 0
            then ok ()
            else returnError

export
fileSize : (h : File) -> IO (Either FileError Int)
fileSize (FHandle f)
    = do res <- primIO (prim__fileSize f)
         if res >= 0
            then ok res
            else returnError

export
fPoll : File -> IO Bool
fPoll (FHandle f)
    = do p <- primIO (prim__fPoll f)
         pure (p > 0)

export
readFile : String -> IO (Either FileError String)
readFile file
  = do Right h <- openFile file Read
          | Left err => returnError
       Right content <- read [] h
          | Left err => do closeFile h
                           returnError
       closeFile h
       pure (Right (fastAppend content))
  where
    read : List String -> File -> IO (Either FileError (List String))
    read acc h
        = do eof <- fEOF h
             if eof
                then pure (Right (reverse acc))
                else
                  do Right str <- fGetLine h
                        | Left err => returnError
                     read (str :: acc) h

||| Write a string to a file
export
writeFile : (filepath : String) -> (contents : String) ->
            IO (Either FileError ())
writeFile fn contents = do
     Right h  <- openFile fn WriteTruncate
        | Left err => pure (Left err)
     Right () <- fPutStr h contents
        | Left err => do closeFile h
                         pure (Left err)
     closeFile h
     pure (Right ())

namespace FileMode
  public export
  data FileMode = Read | Write | Execute

public export
record Permissions where
  constructor MkPermissions
  user   : List FileMode
  group  : List FileMode
  others : List FileMode

mkMode : Permissions -> Int
mkMode p
    = getMs (user p) * 64 + getMs (group p) * 8 + getMs (others p)
  where
    getM : FileMode -> Int
    getM Read = 4
    getM Write = 2
    getM Execute = 1

    getMs : List FileMode -> Int
    getMs = sum . map getM

export
chmodRaw : String -> Int -> IO (Either FileError ())
chmodRaw fname p
    = do ok <- primIO $ prim__chmod fname p
         if ok == 0
            then pure (Right ())
            else returnError

export
chmod : String -> Permissions -> IO (Either FileError ())
chmod fname p = chmodRaw fname (mkMode p)
