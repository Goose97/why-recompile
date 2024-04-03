.PHONY: app release

app:
	elixir --erl "-noinput" -S mix run --no-halt

release:
	echo 'y' | MIX_ENV=prod mix release
	echo 'y' | ./burrito_out/why_recompile_macos_arm maintenance uninstall
	cp ./burrito_out/why_recompile_macos_arm ../ecto
