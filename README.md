## format.sh
Shell script that executes language specific code styling tools (standarjs, black, isort...) on a given file.

### Structure
+ `read_config.py`:
    > A simple python script that allows the reading keys from a config file.
+ `format_watcher.xml`:
    > Configuration file that runs `format.sh` on every file saved by a JetBrains IDE.
