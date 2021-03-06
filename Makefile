.PHONY: test

REBAR=./rebar

all: get-deps compile

compile: get-deps
	@$(REBAR) compile

get-deps:
	@$(REBAR) get-deps

update-deps:
	@$(REBAR) update-deps

xref:
	@$(REBAR) xref skip_deps=true

clean:
	@$(REBAR) clean
	rm -rf rel/emqttd

test:
	@$(REBAR) skip_deps=true eunit

edoc:
	@$(REBAR) doc

dist:
	cd rel && rm -rf im_server.zip && cd ..
	cd rel && ../rebar generate -f && zip  -r im_server.zip im_server
