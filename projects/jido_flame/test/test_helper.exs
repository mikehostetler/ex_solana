# Start ExUnit
ExUnit.start(exclude: [:flaky, :flame_fly])

# Start Mimic for mocking
Mimic.copy(FLAME)
Mimic.copy(FLAME.Pool)
