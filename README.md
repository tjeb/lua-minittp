# lua-minittp
Extremely minimalistic web framework

Slightly inspired by web.py and uhttp, this is (nay, will be) a small web framework that allows you to build dynamic websites without too much scaffolding.

Essentially you get to write a lua script that gets a request and can 
return a response. Simple structures to build and send the various parts of the response are provided. See the examples for more information.

A minimal webserver is provided for local testing, but you should really proxy this through nginx or apache. It supports direct proxying and FastCGI.

Very much Work In Progress.
