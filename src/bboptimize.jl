ValidMethods = {
  :random_search => BlackBoxOptim.random_search,
  :de_rand_1_bin => BlackBoxOptim.de_rand_1_bin,
  :de_rand_2_bin => BlackBoxOptim.de_rand_2_bin,
  :de_rand_1_bin_radiuslimited => BlackBoxOptim.de_rand_1_bin_radiuslimited,
  :de_rand_2_bin_radiuslimited => BlackBoxOptim.de_rand_2_bin_radiuslimited,
  :adaptive_de_rand_1_bin => BlackBoxOptim.adaptive_de_rand_1_bin,
  :adaptive_de_rand_1_bin_radiuslimited => BlackBoxOptim.adaptive_de_rand_1_bin_radiuslimited,
  :separable_nes => BlackBoxOptim.separable_nes,
  :xnes => BlackBoxOptim.xnes,
  :resampling_memetic_search => BlackBoxOptim.resampling_memetic_searcher,
  :resampling_inheritance_memetic_search => BlackBoxOptim.resampling_inheritance_memetic_searcher,
  :simultaneous_perturbation_stochastic_approximation => BlackBoxOptim.SimultaneousPerturbationSA2
}

MethodNames = collect(keys(ValidMethods))

# Default parameters for all convenience methods that are exported to the end user.
DefaultParameters = {
  :NumDimensions  => :NotSpecified, # Dimension of problem to be optimized
  :SearchRange    => (-10.0, 10.0), # Default search range to use per dimension unless specified
  :SearchSpace    => false, # Search space can be directly specified and takes precedence over Dimension and SearchRange if specified.

  :MaxTime        => false,   # Max time in seconds (takes precedence over the other budget-related params if specified)
  :MaxFuncEvals   => false,   # Max func evals (takes precedence over max iterations, but not max time)
  :MaxSteps       => 10000,   # Max iterations gives the least control since different optimizers have different "size" of their "iterations"
  :MinDeltaFitnessTolerance => 1e-11, # Minimum delta fitness (difference between two consecutive best fitness improvements) we can accept before terminating
  :FitnessTolerance => 1e-8,  # Stop optimization when the best fitness found is within this distance of the actual optimum (if known)

  :NumRepetitions => 1,     # Number of repetitions to run for each optimizer for each problem

  :ShowTrace      => true,  # Print tracing information during the optimization
  :TraceInterval  => 0.50,  # Minimum number of seconds between consecutive trace messages printed to STDOUT
  :SaveTrace      => false, 
  :SaveFitnessTraceToCsv => false, # Save a csv file with information about the major fitness improvement events (only the first event in each fitness magnitude class is saved)
  :SaveParameters => false, # Save parameters to a json file for later scrutiny

  :RandomizeRngSeed => true, # Randomize the RngSeed value before using any random numbers.
  :RngSeed        => 1234,   # The specific random seed to set before any random numbers are generated. The seed is randomly selected if RandomizeRngSeed is true, and this parameter is updated with its actual value.

  :PopulationSize => 50
}

# Create a problem given 
#   a problem or 
#   a function and a search range or
#   a function and a
# while possibly updating the params with the specific dimension and search 
# space to be used.
function setup_problem(functionOrProblem; parameters = Dict())

  params = Parameters(parameters, DefaultParameters)

  # If an OptimizationProblem was given it takes precedence over the search range param setting.
  if issubtype(typeof(functionOrProblem), OptimizationProblem)

    # If a fixed dim problem was given it takes precedence over the dimension param setting.
    if typeof(functionOrProblem) == FixedDimProblem
      problem = functionOrProblem
    else 
      # If an anydim problem was given the dimension param must have been specified.
      if params[:NumDimensions] == :NotSpecified
        throw(ArgumentError("You MUST specify the number of dimensions in a solution when an any-dimensional problem is given"))
      else
        problem = as_fixed_dim_problem(functionOrProblem, parameters[:NumDimensions])
      end
    end

  elseif typeof(functionOrProblem) == Function

    # Check that a valid search space has been stated and create the search_space
    # based on it, or bail out.
    if typeof(params[:SearchRange]) == typeof( (0.0, 1.0) )
      if params[:NumDimensions] == :NotSpecified
        throw(ArgumentError("You MUST specify the number of dimensions in a solution when giving a search range $(searchRange)"))
      end
      params[:SearchSpace] = symmetric_search_space(params[:NumDimensions], params[:SearchRange])
    elseif typeof(params[:SearchRange]) == typeof( [(0.0, 1.0)] )
      params[:SearchSpace] = RangePerDimSearchSpace(params[:SearchRange])
      params[:NumDimensions] = length(params[:SearchRange])
    else
      throw(ArgumentError("Invalid search range specification."))
    end

    # Now create an optimization problem with the given information. We currently reuse the type
    # from our pre-defined problems so some of the data for the constructor is dummy.
    problem = fixeddim_problem(functionOrProblem; 
      search_space = params[:SearchSpace], range = params[:SearchRange],
      dims = params[:NumDimensions]
    )

  end

  params[:SearchSpace] = search_space(problem)

  return problem, params

end

function compare_optimizers(functionOrProblem::Union(Function, OptimizationProblem); 
  max_time = false, search_space = false, search_range = (0.0, 1.0), dimensions = 2,
  methods = MethodNames, parameters = Dict())

  params = Parameters(parameters, DefaultParameters)

  results = Any[]
  for(m in methods)
    tic()
    best, fitness, reason = bboptimize(functionOrProblem; method = m, parameters = parameters,
      max_time = max_time, search_space = search_space, dimensions = dimensions,
      search_range = search_range)
    push!( results,  (m, best, fitness, toq()) )
  end

  sorted = sort( results, by = (t) -> t[3] )

  if params[:ShowTrace]
    for(i in 1:length(sorted))
      println("$(i). $(sorted[i][1]), fitness = $(sorted[i][3]), time = $(sorted[i][4])")
    end
  end

  return sorted

end

function compare_optimizers(problems::Dict{Any, FixedDimProblem}; max_time = false,
  methods = MethodNames, parameters = Dict())

  # Lets create an array where we will save how the methods ranks per problem.
  ranks = zeros(length(methods), length(problems))
  fitnesses = zeros(Float64, length(methods), length(problems))
  times = zeros(Float64, length(methods), length(problems))

  problems = collect(problems)

  for i in 1:length(problems)
    name, p = problems[i]
    res = compare_optimizers(p; max_time = max_time, methods = methods, parameters = parameters)
    for(j in 1:length(res))
      method, best, fitness, elapsedtime = res[j]
      index = findfirst(methods, method)
      ranks[index, i] = j
      fitnesses[index, i] = fitness
      times[index, i] = elapsedtime
    end
  end

  avg_ranks = round(mean(ranks, 2), 2)
  avg_fitness = round(mean(fitnesses, 2), 3)
  avg_times = round(mean(times, 2), 2)

  perm = sortperm(avg_ranks[:])
  println("\nBy avg rank:")
  for(i in 1:length(methods))
    j = perm[i]
    print("\n$(i). $(methods[j]), avg rank = $(avg_ranks[j]), avg fitness = $(avg_fitness[j]), avg time = $(avg_times[j]), ranks = ")
    showcompact(ranks[j,:][:])
  end

  perm = sortperm(avg_fitness[:])
  println("\n\nBy avg fitness:")
  for(i in 1:length(methods))
    j = perm[i]
    print("\n$(i). $(methods[j]), avg rank = $(avg_ranks[j]), avg fitness = $(avg_fitness[j]), avg time = $(avg_times[j]), ranks = ")
    showcompact(ranks[j,:][:])
  end

  return ranks, fitnesses
end

function bboptimize(functionOrProblem; max_time = false,
  search_space = false, search_range = (0.0, 1.0), dimensions = 2,
  method = :adaptive_de_rand_1_bin_radiuslimited, 
  parameters = Dict())

  params = Parameters(parameters, DefaultParameters)
  params[:MaxTime] = max_time
  params[:SearchSpace] = search_space
  params[:SearchRange] = search_range
  params[:NumDimensions] = dimensions

  problem, params = setup_problem(functionOrProblem; parameters = params)

  # Create a random solution from the search space and ensure that the given function returns a Number.
  ind = rand_individual(params[:SearchSpace])
  res = eval1(ind, problem)
  if !(typeof(res) <: Number)
    throw(ArgumentError("The supplied function does NOT return a number when called with a potential solution (when called with $(ind) it returned $(res)) so we cannot optimize it!"))
  end

  # Check that max_time is larger than zero if it has been specified.
  if params[:MaxTime] != false
    if params[:MaxTime] <= 0.0
      throw(ArgumentError("The max_time must be a positive number"))
    else
      params[:MaxTime] = convert(Float64, params[:MaxTime])
    end
  end

  # Check that a valid number of iterations has been specified. Print warning if higher than 1e8.
  if params[:MaxFuncEvals] != false
    if params[:MaxFuncEvals] < 1
      throw(ArgumentError("The number of function evals MUST be a positive number"))
    elseif params[:MaxFuncEvals] >= 1e8
      println("Number of allowed function evals is $(params[:MaxFuncEvals]); this can take a LONG time")
    end
  end

  # Check that a valid number of iterations has been specified. Print warning if higher than 1e8.
  if params[:MaxSteps] < 1
    throw(ArgumentError("The number of iterations MUST be a positive number"))
  elseif params[:MaxSteps] >= 1e7
    println("Number of allowed iterations is $(params[:MaxSteps]); this can take a LONG time")
  end

  # Check that a valid population size has been given.
  if params[:PopulationSize] < 2
    throw(ArgumentError("The population size MUST be at least 2"))
  end

  # Check that a valid method has been specified and then set up the optimizer
  if (typeof(method) != Symbol) || !any([(method == vm) for vm in MethodNames])
    throw(ArgumentError("The method specified, $(method), is NOT among the valid methods: $(MethodNames)")) 
  end
  pop = BlackBoxOptim.rand_individuals_lhs(params[:SearchSpace], params[:PopulationSize])

  params = Parameters(params, {
    :Evaluator    => ProblemEvaluator(problem),
    :Population   => pop,
    :SearchSpace  => search_space
  })
  optimizer_func = ValidMethods[method]
  optimizer = optimizer_func(params)

  run_optimizer_on_problem(optimizer, problem; parameters = params)
end

function tr(msg, parameters, obj = None)
  if parameters[:ShowTrace]
    print(msg)
    if obj != None
      showcompact(obj)
    end
  end
  if parameters[:SaveTrace]
    # No saving for now
  end
end

function find_best_individual(e::Evaluator, opt::PopulationOptimizer)
  (best_candidate(e.archive), 1, best_fitness(e.archive))
end

function find_best_individual(e::Evaluator, opt::Optimizer)
  (best_candidate(e.archive), 1, best_fitness(e.archive))
end

function run_optimizer_on_problem(opt::Optimizer, problem::OptimizationProblem;
  parameters = Dict())

  if parameters[:RandomizeRngSeed]
    parameters[:RngSeed] = rand(1:int(1e6))
    srand(parameters[:RngSeed])
  end

  # No max time if unspecified. If max time specified it takes precedence over
  # max_steps and MaxFuncEvals. If no max time MaxFuncEvals takes precedence over
  # MaxSteps.
  if parameters[:MaxTime] == false
    max_time = Inf
    if parameters[:MaxFuncEvals] != false
      max_fevals = parameters[:MaxFuncEvals]
      max_steps = Inf
    else
      max_steps = parameters[:MaxSteps]
      max_fevals = Inf
    end
  else
    max_steps = Inf
    max_fevals = Inf
    max_time = parameters[:MaxTime]
  end

  # Now set up an evaluator for this problem. This will handle fitness
  # comparisons, keep track of the number of function evals as well as
  # keep an archive and top list.
  evaluator = get(parameters, :Evaluator, ProblemEvaluator(problem))

  num_better = 0
  num_better_since_last = 0
  tr("Starting optimization with optimizer $(name(opt))\n", parameters)

  step = 1
  t = last_report_time = start_time = time()
  elapsed_time = 0.0

  termination_reason = "" # Will be set in loop below...

  while( true )

    if elapsed_time > max_time
      termination_reason = "Max time reached"
      break
    end

    if num_evals(evaluator) > max_fevals
      termination_reason = "Max number of function evaluations reached"
      break
    end

    if step > max_steps
      termination_reason = "Max number of steps reached"
      break
    end

    if delta_fitness(evaluator.archive) < parameters[:MinDeltaFitnessTolerance]
      termination_reason = "Delta fitness below tolerance"
      break
    end

    if fitness_is_within_ftol(evaluator, parameters[:FitnessTolerance])
      termination_reason = "Within fitness tolerance of optimum"
      break
    end

    # Report on progress every now and then...
    if (t - last_report_time) > parameters[:TraceInterval]
      last_report_time = t
      num_better += num_better_since_last

      # Always print step number, num fevals and elapsed time
      tr(@sprintf("%.2f secs, %d evals , %d steps", 
        elapsed_time, num_evals(evaluator), step), parameters) 

      # Only print if this optimizer reports on number of better. They return 0
      # if they do not.
      if num_better_since_last > 0
        tr(@sprintf(", improv/step: %.3f (last = %.4f)", 
          num_better/step, num_better_since_last/step), parameters)
        num_better_since_last = 0
      end

      # Always print fitness if num_evals > 0
      if num_evals(evaluator) > 0
        tr(@sprintf(", %.9f", best_fitness(evaluator.archive)), parameters)
      end

      tr("\n", parameters)
    end

    if has_ask_tell_interface(opt)

      # They ask and tell interface is more general since you can mix and max
      # elements from several optimizers using it. However, in this top-level
      # execution function we do not make use of this flexibility...
      candidates = ask(opt)
      ranked_candidates = BlackBoxOptim.rank_by_fitness(evaluator, candidates)
      num_better_since_last += tell!(opt, ranked_candidates)

    else

      BlackBoxOptim.step(opt)
      num_better_since_last = 0

    end

    step += 1
    t = time()
    elapsed_time = t - start_time
  end

  step -= 1 # Since it is one too high after while loop above

  tr("\nOptimization stopped after $(step) steps and $(elapsed_time) seconds\n", parameters)
  tr("Termination reason: $(termination_reason)\n", parameters)
  tr("Steps per second = $(step/elapsed_time)\n", parameters)
  tr("Function evals per second = $(num_evals(evaluator)/elapsed_time)\n", parameters)
  tr("Improvements/step = $((num_better+num_better_since_last)/max_steps)\n", parameters)
  if typeof(opt) <: PopulationOptimizer
    tr("\nMean value (in population) per position:", parameters, mean(population(opt),1))
    tr("\n\nStd dev (in population) per position:", parameters, std(population(opt),1))
  end
  best, index, fitness = find_best_individual(evaluator, opt)
  tr("\n\nBest candidate found: ", parameters, best)
  tr("\n\nFitness: ", parameters, fitness)
  tr("\n\n", parameters)

  if parameters[:SaveFitnessTraceToCsv]
    optname = replace(name(optimizer), r"\s+", "_")
    archive = evaluator.archive
    # Save history to csv file here...
  end

  return best, fitness, termination_reason, elapsed_time
end