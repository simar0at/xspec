xquery version "3.1";
module namespace _ = "http://www.jenitennison.com/xslt/xspec/rest";

import module namespace rest = "http://exquery.org/ns/restxq";
import module namespace jobs = "http://basex.org/modules/jobs";
import module namespace db = "http://basex.org/modules/db";
import module namespace request = "http://exquery.org/ns/request";
import module namespace xslt = "http://basex.org/modules/xslt";
import module namespace l = "http://basex.org/modules/admin";

declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace x = "http://www.jenitennison.com/xslt/xspec";

declare variable $_:path-to-stylesheets := "../src/";

declare 
    %rest:path("xspec/run")
    %rest:query-param("raw", "{$raw}", "false")
    %rest:query-param("xspec", "{$xspec-location}", '../tutorial/xquery-tutorial.xspec')
    %rest:GET
    %output:method("xml")
function _:main($xspec-location as xs:string, $raw as xs:string) as item()+ {
let $xspec := _:get-xspec($xspec-location)
  , $testQuery := _:xsl-transform-to-xquery($xspec)
  , $testId := jobs:eval($testQuery, (), map {'cache': true() }), $_ := jobs:wait($testId)
  , $testStats := jobs:list-details()[@id=$testId]
  , $testResults := jobs:result($testId)
return if ($raw ne "false") then $testResults else _:create-html-response($testResults)
};

declare %private function _:create-html-response($testResults as element()) { 
let $formatted := _:xsl-transform(_:get-xsl("reporter/format-xspec-report"), $testResults)
return 
  (<rest:response>
      <http:response>
          <http:header name="Content-Type" value="text/html; charset=utf-8"/>
      </http:response>
  </rest:response>,
  $formatted)  
};

declare %private function _:get-xsl($mode as xs:string) as document-node()? {
  let $openjob := jobs:eval('declare variable $mode external;&#10;'||
  'if ($mode != '''' and doc-available("'||$_:path-to-stylesheets||$mode||'.xsl")) then doc("'||$_:path-to-stylesheets||$mode||'.xsl")&#10;'||
  'else ()', map {"mode": $mode}, map {'cache': true() }), $_ := jobs:wait($openjob)
  return jobs:result($openjob)
};

declare %private function _:get-xspec($location as xs:string) as document-node() {
  let $openjob := jobs:eval('declare variable $location external;&#10;'||
  'if ($location != '''' and doc-available("'||$location||'")) then doc("'||$location||'")&#10;'||
  'else ()', map {"location": $location}, map {'cache': true() }), $_ := jobs:wait($openjob)
  return jobs:result($openjob)
};

declare %private function _:xsl-transform($xsl as document-node(), $testResult as element()) as document-node() {
xslt:transform($testResult, $xsl, map{"report-css-uri": "/xspec/test-report.css"})  
};

declare %private function _:xsl-transform-to-xquery($input as document-node()) as xs:string {
let $xsl := _:get-xsl("compiler/generate-query-tests")
return xslt:transform-text($input, $xsl,
  map{
      "query-at": string-join(tokenize(base-uri($input), '/')[last() > position()], '/')||'/'||$input/x:description/@query-at
  })  
};

(: REST/http helper functions :)
(:~
 : Returns a html or related file.
 : @param  $file  file or unknown path
 : @return rest response and binary file
 :)
declare
  %rest:path("xspec/{$file=[^/]+}")
function _:file($file as xs:string) as item()+ {
  let $path := _:base-dir()||$file
  return if (file:exists($path)) then
    if (matches($file, '\.(htm|html|js|map|css|png|gif|jpg|jpeg|woff|woff2)$', 'i')) then
    (
      web:response-header(map { 'media-type': web:content-type($path) }, 
                          map { 'X-UA-Compatible': 'IE=11' }),
      file:read-binary($path)
    )
    else _:forbidden-file($file)
  else
  (
  <rest:response>
    <http:response status="404" message="{$file} was not found.">
      <http:header name="Content-Language" value="en"/>
      <http:header name="Content-Type" value="text/html; charset=utf-8"/>
    </http:response>
  </rest:response>,
  <html xmlns="http://www.w3.org/1999/xhtml">
    <title>{$file||' was not found'}</title>
    <body>        
       <h1>{$file||' was not found at '||$path}</h1>
    </body>
  </html>
  )
};

declare %private function _:base-dir() as xs:string {
  replace(file:base-dir(), '^(.+)bin.*$', '$1/src/reporter/')
};

(:~
 : Returns index.html on /.
 : @param  $file  file or unknown path
 : @return rest response and binary file
 :)
declare
  %rest:path("xspec")
function _:index-file() as item()+ {
  let $index-html := _:base-dir()||'index.html',
      $index-htm := _:base-dir()||'index.htm',
      $uri := rest:uri(),
(:      $log := l:write-log('_:index-file() $uri := '||$uri||' base-uri-public := '||_:get-base-uri-public(), 'DEBUG'),:)
      $absolute-prefix := if (matches(_:get-base-uri-public(), '/$')) then () else _:get-base-uri-public()||'/'
  return if (exists($absolute-prefix)) then
    <rest:redirect>{$absolute-prefix}</rest:redirect>
  else if (file:exists($index-html)) then
    <rest:forward>index.html</rest:forward>
  else if (file:exists($index-htm)) then
    <rest:forward>index.htm</rest:forward>
  else <rest:forward>run</rest:forward>    
};

(:~
 : Return 403 on all other (forbidden files).
 : @param  $file  file or unknown path
 : @return rest response and binary file
 :)
declare
  %private
function _:forbidden-file($file as xs:string) as item()+ {
  <rest:response>
    <http:response status="403" message="{$file} forbidden.">
      <http:header name="Content-Language" value="en"/>
      <http:header name="Content-Type" value="text/html; charset=utf-8"/>
    </http:response>
  </rest:response>,
  <html xmlns="http://www.w3.org/1999/xhtml">
    <title>{$file||' forbidden'}</title>
    <body>        
       <h1>{$file||' forbidden'}</h1>
    </body>
  </html>
};

declare function _:get-base-uri-public() as xs:string {
    let $forwarded-hostname := if (contains(request:header('X-Forwarded-Host'), ',')) 
                                 then substring-before(request:header('X-Forwarded-Host'), ',')
                                 else request:header('X-Forwarded-Host'),
        $urlScheme := if ((lower-case(request:header('X-Forwarded-Proto')) = 'https') or 
                          (lower-case(request:header('Front-End-Https')) = 'on')) then 'https' else 'http',
        $port := if ($urlScheme eq 'http' and request:port() ne 80) then ':'||request:port()
                 else if ($urlScheme eq 'https' and not(request:port() eq 80 or request:port() eq 443)) then ':'||request:port()
                 else '',
        (: FIXME: this is to naive. Works for ProxyPass / to /exist/apps/cr-xq-mets/project
           but probably not for /x/y/z/ to /exist/apps/cr-xq-mets/project. Especially check the get module. :)
        $xForwardBasedPath := (request:header('X-Forwarded-Request-Uri'), request:path())[1]
    return $urlScheme||'://'||($forwarded-hostname, request:hostname())[1]||$port||$xForwardBasedPath
};