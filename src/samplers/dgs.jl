#################### Discrete Gibbs Sampler ####################

#################### Types and Constructors ####################

const DGSUnivariateDistribution =
          Union{Bernoulli, Binomial, Categorical, DiscreteUniform,
                Hypergeometric, NoncentralHypergeometric}


const DSForm = Union{Function, Vector{Float64}}

type DSTune{F<:DSForm} <: SamplerTune
  mass::Nullable{F}
  support::Matrix{Real}

  DSTune{F}() where F<:DSForm = new()

  DSTune{F}(x::Vector, support::AbstractMatrix) where F<:DSForm =
    new(Nullable{Function}(), support)

  DSTune{F}(x::Vector, support::AbstractMatrix, mass::Function) where
    F<:DSForm = new(Nullable{F}(mass), support)
end


const DGSVariate = SamplerVariate{DSTune{Function}}
const DiscreteVariate = SamplerVariate{DSTune{Vector{Float64}}}

validate(v::DGSVariate) = validate(v, v.tune.support)

function validate(v::DiscreteVariate)
  validate(v, v.tune.support)
  validate(v, v.tune.support, v.tune.mass)
end

function validate{F<:DSForm}(v::SamplerVariate{DSTune{F}}, support::Matrix)
  n = length(v)
  size(support, 1) == n ||
    throw(ArgumentError("size(support, 1) differs from variate length $n"))
  v
end

validate(v::DiscreteVariate, support::Matrix, mass::Nullable{Vector{Float64}}) =
  isnull(mass) ? v : validate(v, support, get(mass))

function validate(v::DiscreteVariate, support::Matrix, mass::Vector{Float64})
  n = length(mass)
  size(support, 2) == n ||
    throw(ArgumentError("size(support, 2) differs from mass length $n"))
  v
end


#################### Sampler Constructor ####################

function DGS(params::ElementOrVector{Symbol})
  params = asvec(params)
  samplerfx = function(model::Model, block::Integer)
    s = model.samplers[block]
    local node, x
    for key in params
      node = model[key]
      x = unlist(node)

      sim = function(i::Integer, d::DGSUnivariateDistribution, mass::Function)
        v = DGSVariate([x[i]], support(d)')
        sample!(v, mass)
        x[i] = v[1]
        relist!(model, x, key)
      end

      mass = function(d::DGSUnivariateDistribution, v::AbstractVector,
                      i::Integer)
        x[i] = value = v[1]
        relist!(model, x, key)
        exp(logpdf(d, value) + logpdf(model, node.targets))
      end

      DGS_sub!(node.distr, sim, mass)
    end
    nothing
  end
  Sampler(params, samplerfx, DSTune{Function}())
end


function DGS_sub!(d::UnivariateDistribution, sim::Function, mass::Function)
  sim(1, d, v -> mass(d, v, 1))
end

function DGS_sub!(D::Array{UnivariateDistribution}, sim::Function,
                  mass::Function)
  for i in 1:length(D)
    d = D[i]
    sim(i, d, v -> mass(d, v, i))
  end
end

function DGS_sub!(d, sim::Function, mass::Function)
  throw(ArgumentError("unsupported distribution structure $(typeof(d))"))
end


#################### Sampling Functions ####################

sample!{F<:DSForm}(v::SamplerVariate{DSTune{F}}) = sample!(v, v.tune.mass)


function sample!(v::DGSVariate, mass::Function)
  tune = v.tune
  n = size(tune.support, 2)
  probs = Vector{Float64}(n)
  psum = 0.0
  for i in 1:n
    value = mass(tune.support[:, i])
    probs[i] = value
    psum += value
  end
  if psum > 0
    probs /= psum
  else
    probs[:] = 1 / n
  end
  v[:] = tune.support[:, rand(Categorical(probs))]
  v
end


function sample!(v::DiscreteVariate, mass::Vector{Float64})
  validate(v, v.tune.support, mass)
  v[:] = v.tune.support[:, rand(Categorical(mass))]
  v
end
