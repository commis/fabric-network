
all: up

.PHONY: up
up:
	@cd scripts && ./network_setup.sh -t up

.PHONY: down
down:
	@cd scripts && ./network_setup.sh -t down

.PHONY: clean
clean:
	@echo "every thing is clean up, no worry"
