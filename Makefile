
all: up

up:
	@cd scripts && ./network_setup.sh -t up

down:
	@cd scripts && ./network_setup.sh -t down

.PHONY: clean
clean:
	@echo "every thing is clean up, no worry"
