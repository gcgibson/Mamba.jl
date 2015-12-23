#################### Discrete Gibbs Sampler ####################

#################### Types and Constructors ####################

typealias DGSUnivariateDistribution
          Union{Bernoulli, Binomial, Categorical, DiscreteUniform,
                Hypergeometric, NoncentralHypergeometric}

type DGSTune <: SamplerTune
  support::Matrix{Real}
  probs::Vector{Float64}

  function DGSTune(value::Vector{Float64}=Float64[])
    new(
      Array(Float64, 0, 0),
      Array(Float64, 0)
    )
  end
end


typealias DGSVariate SamplerVariate{DGSTune}


#################### Sampler Constructor ####################

function DGS(params::ElementOrVector{Symbol})
  params = asvec(params)
  samplerfx = function(model::Model, block::Integer)
    s = model.samplers[block]
    local node, x
    for key in params
      node = model[key]
      x = unlist(node)

      sim = function(i::Integer, d::UnivariateDistribution, logf::Function)
        v = SamplerVariate([x[i]], s, model.iter)
        dgs!(v, d, logf)
        x[i] = v[1]
        relist!(model, x, key)
      end

      logf = function(d::UnivariateDistribution, v::AbstractVector, i::Integer)
        x[i] = value = v[1]
        relist!(model, x, key)
        logpdf(d, value) + logpdf(model, node.targets)
      end

      DGS_sub!(node.distr, sim, logf)
    end
    nothing
  end
  Sampler(params, samplerfx, DGSTune())
end

function DGS_sub!(d::UnivariateDistribution, sim::Function, logf::Function)
  sim(1, d, v -> logf(d, v, 1))
end

function DGS_sub!(D::Array{UnivariateDistribution}, sim::Function,
                  logf::Function)
  for i in 1:length(D)
    d = D[i]
    sim(i, d, v -> logf(d, v, i))
  end
end

function DGS_sub!(d, sim::Function, logf::Function)
  throw(ArgumentError("unsupported distribution structure $(typeof(d))"))
end


#################### Sampling Functions ####################

function dgs!{T<:Real}(v::DGSVariate, support::Matrix{T}, logf::Function)
  n = size(support, 1)
  probs = Array(Float64, n)
  psum = 0.0
  for i in 1:n
    x = vec(support[i, :])
    value = exp(logf(x))
    probs[i] = value
    psum += value
  end
  if psum > 0
    probs /= psum
  else
    probs[:] = 1 / n
  end
  v[:] = support[rand(Categorical(probs)), :]
  v.tune.support = support
  v.tune.probs = probs
  v
end

function dgs!{T<:Real}(v::DGSVariate, support::Matrix{T},
                       probs::Vector{Float64})
  size(support, 1) == length(probs) ||
    throw(ArgumentError("numbers of support rows and probs differ"))

  v[:] = support[rand(Categorical(probs)), :]
  v.tune.support = support
  v.tune.probs = probs
  v
end

function dgs!(v::DGSVariate, d::DGSUnivariateDistribution, logf::Function)
  S = support(d)
  dgs!(v, reshape(S, length(S), 1), logf)
end

function dgs!(v::DGSVariate, d::Distribution, logf::Function)
  throw(ArgumentError("unsupported distribution $(typeof(d))"))
end
