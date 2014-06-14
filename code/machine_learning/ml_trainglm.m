function model = ml_trainglm(varargin)
% Variational Bayesian estimation in a Generalized Linear Model.
% Model = ml_trainglm(Trials, Targets, Options...)
%
% This method allows to learn parameters of a generalized linear model (GLM) set up to predict some
% target variable in which the unknowns are estimated using Variational Bayesian (VB) inference
% (yielding the posterior mean and covariance). The model is quite flexible and allows to set up
% multiple priors with Gaussian or super-Gaussian (e.g., Laplace, Sech^2, Student-T) distributions,
% possibly linked to the unknowns via known linear transformations (such as Wavelet, finite
% differences, Fourier transform), and can perform both regression and classification. However, the
% specification of the model is quite complicated due to the flexibility, so advanced functionality
% is only usable by experts.
%
% In:
%   Trials       : training data, as in ml_train
%                  in addition, it may be specified as UxVxN 3d matrix,
%                  with UxV-formatted feature matrices per trial (N trials), or
%                  as {{U1xV1,U2xV2,...}, {U1xV1,U2xV2,...}
%
%   Targets      : target variable, as in ml_train
%
%   Lambdas : Noise variance parameter. If multiple values are given, the one with the best evidence
%             is chosen. A good default value is 1. (default: 2.^(-4:0.5:4))
%
%
% Out:
%   Models   : a predictive model
%
% See also:
%   ml_predictglm, dli
%
%                                Christian Kothe, Swartz Center for Computational Neuroscience, UCSD
%                                2011-07-08

% example: {'glm','Type','Regression','Priors',{'Term1',{'Laplace','@(x)diff(x,2)'}}};

% define common parameters of different distributions
common_parameters = { ...
        arg({'B','LinearOperator'},'@(x)x(:)''',[],'Linear transform. The distribution applies to the linearly transformed weight vector. Either an expression that is evaluated in the workspace or a function handle. When defining the linear operator as an anonymous function, the variables a to h can be used to refer to the sizes of the first 8 dimensions of x.'), ...
        arg({'G','Groups'},[],[],'Grouping matrix. Sparse matrix whose columns are indicator vectors for the respective groups in the linearly transformed data (under linear indexing). If empty, the columns of the linearly transformed data are taken as the groups.'), ...
        arg({'tau','Scales'},1,[],'Scales of the potential. Allows for scaling of the distributions.','shape','row'), ...
        arg({'tauSearch','ScalesSearch'},true,[],'Use Scales as regularization parameter. If enabled, multiple values can be given and will be searched over in a grid search (possibly together with other hyper-parameters); if unchecked, multiple values are assumed to apply to different features after application of the linear operator.'), ...
        arg({'t','Shifts'},0,[],'Shifts for an affine transform. Allows for shifting of the distributions.'), ...
    };

% define the possible distributions supported by glm-ie
distributions = @(argname) arg_subswitch({lower(argname),argname},{'none'},{ ...
        'none', {}, ...
        'Laplace', common_parameters, ...
        'Gaussian', [common_parameters {arg({'appendToX','AppendToX'},true,[],'Append to X matrix instead of B. If true, the Scales parameter will be ignored and the global Lambdas will be used instead (and may be searched). This is probably better unless per-feature control of scales is desired. This setting will be ignored if there is otherwise no potential at B.')}], ...
        'Logistic', common_parameters, ...
        'StudentT',[common_parameters {arg({'nu','DegreesOfFreedom'},1,[1 Inf],'Degrees of freedom. If multiple values are given the optimal one will be determined by evidence maximization.','shape','row')}], ...
        'Sech2', common_parameters, ...
        'ExpPow',[common_parameters {arg({'alpha','ShapeExponent'},8,[0 Inf],'Shape parameter (exponent). This is the beta parameter of a type-1 generalized Gaussian distribution.  If multiple values are given the optimal one will be determined by evidence maximization.','shape','row')}]...
    }, 'Distribution type. Defines a parametric prior distribution applied to a linear transform of the data.');

% define the arguments of ml_trainglm()
args = arg_define([0 2],varargin, ...
    arg_norep('trials'), ...
    arg_norep('targets'), ...
    ... % problem setup
    arg({'lambdas','NoiseVariance','Lambdas'}, 2.^(-4:0.5:4), [0 Inf], 'Gaussian noise variance. If multiple values are given, the one with the best evidence is used. A good search range is 2.^(-4:0.5:4). Note: this only applies to Gaussian terms -- e.g., in linear regression or when using a Gaussian prior in logistic regression.','shape','row'), ...
    arg({'ptype','Type'}, 'classification', {'classification','regression'}, 'Type of problem to solve.'), ...
    arg_sub({'priors','Priors'},{},{ ...
        distributions('Term1'), ...
        distributions('Term2'), ...
        distributions('Term3'), ...
        distributions('Term4'), ...
        distributions('Term5'), ...
        distributions('Term6'), ...
        distributions('Term7')}, 'Definition of the prior terms. Any combination of terms is permitted.'), ...
    arg_nogui({'shape','Shape'}, [], [], 'Reshaping for features. Allows to reshape (perhaps vectorized) features into a particular representation.','shape','row'), ...
    arg({'scaling','Scaling'}, 'std', {'none','center','std','minmax','whiten'}, 'Pre-scaling of the data. For the regulariation to work best, the features should either be naturally scaled well, or be artificially scaled.'), ...
    arg({'includeBias','IncludeBias','bias','includebias'},true,[],'Include bias param. Also learns an unregularized bias param (strongly recommended for typical classification problems).'), ...
    arg_sub({'solverOptions','SolverOptions'},{},{
        arg({'outerNiter','OuterIterations'},10,uint32([1 5 25 1000]),'Outer loop iterations.'),...
        arg({'innerMVM','InnerIterations'},50,uint32([1 10 150 1000]),'Inner-loop iterations. Number of matrix-vector multiplications and/or conjugate gradient steps to perform in inner loop.'),...
        arg_subswitch({'outerMethod','OuterMethod'},'Lanczos',{ ...
            'full',{}, ...    
            'Lanczos',{ ...
                arg({'MVM','LanczosVectors'},50,uint32([1 10 100 1000]),'Number of Lanczos vectors. This is the precision of the variational approximation. More more will yield a more complete posterior approximation.')},...
            'sample',{ ...
                arg({'NSamples','NumSamples'},10,uint32([1 5 100 1000]),'Number of Monte Carlo samples.'), ...
                arg({'Ncg','NumCGSteps'},20,uint32([1 5 100 1000]),'Number of Conjugate-Gradient steps.')}, ...
            'Woodbury',{}, ...
            'factorial',{}},'Posterior covariance algorithm. The ''full'' method produces an exact dense matrix, ''lanczos'' produces a low-rank approximation with a given number of Lanczos vectors, ''sample'' calculates a Monte Carlo estimate, ''woodbury'' calculates an exact solution using the Woodbury formula, requires that B=I, ''factorial'' yields a factorial (mean-field) estimate.'),...
        arg_subswitch({'innerVBpls','InnerMethod'},'Conjugate Gradients',{ ...
            'Quasi-Newton',{ ...
                arg({'LBFGSnonneg','NonNegative'},false,[],'Non-negative. Whether to restrict the solution space to non-negative values.','guru',true),...
            }, ... 
            'Truncated Newton',{ ...
                arg({'nit','NewtonSteps'},15,uint32([1 5 50 1000]),'Number of Newton steps.'),...
                arg({'nline','LineSearchSteps'},10,uint32([1 3 50 1000]),'Max line-search steps. Maximum number of bisections in Brent''s line-search algorithm.','guru',true),...
                arg({'exactNewt','ExactNewton'},false,[],'Compute exact direction. This is instead of CG; works only if B=1 and X is numeric.','guru',true),...
            },...
            'Backtracking Conjugate Gradients',{...
                arg({'nline','LineSearchSteps'},20,uint32([1 3 50 1000]),'Max line-search steps. Maximum number of backtracking steps in line search.','guru',true),...        
                arg({'al','ArmijoAlpha'},0.01,[0 0.001 1 Inf],'Armijo alpha parameters. Parameter in Armijo-rule line search.','guru',true),...        
                arg({'be','ArmijoShrink'},0.6,[0 0.1 0.9 1],'Armijo shrinking parameter. This is the beta or tau shrinking parameter in the line search.','guru',true),...        
                arg({'cmax','MaxStepsize'},1,[0 Inf],'Maximum stepsize. Scaling factor for the gradient direction.','guru',true),...        
                arg({'eps_grad','GradientTol'},1e-10,[0 Inf],'Gradient norm convergence threshold.','guru',true),...
                arg({'nrestart','NumRestarts'},0,uint32([0 0 10 100]),'Max CG restarts.','guru',true),...
            }, ...
            'Conjugate Gradients', {...
            }, ...
            'Split-Bregman',{...            
                arg({'SBeta','ConstraintCoefficient'},1,[],'Coefficient for constraint term. Data is rescaled such that 1 should work.','guru',true),...        
                arg({'SBga','RegularizationParameter'},[],[],'Regularization parameter. Best to leave unspecified; default is then 0.01/lambda.','guru',true),...        
                arg({'SBinner','InnerSteps'},30,uint32([1 5 100 1000]),'Number of (inner) loop steps. For the constraint. Sometimes 5-10 iterations are OK.'),...
                arg({'SBouter','OuterSteps'},15,uint32([1 5 100 1000]),'Number of (outer) Bregman iterations.'),...
                arg({'SBncg','CGSteps'},50,uint32([1 5 100 1000]),'Number of CG steps.'),...
            }, ...
            'Barzilai-Borwein',{...
                arg({'eps_grad','GradientTol'},1e-10,[0 Inf],'Gradient norm convergence threshold.','guru',true),...
                arg({'plsBBstepsizetype','UseEquationFive'},true,[],'Use equation 5 for update. Otherwise uses (equivalent) equation 6 from BB paper.','guru',true),...
            }},'PLS solver. Penalized least-squares solver to use in the inner loop; Quasi-Newton (L-BFGS) is one of the most efficient method, but depends on C code; Truncated-Newton performs TN with CG-approximated Newton steps, Backtracking Conjugate Gradients uses CG with Armijo backtracking, Conjugate Gradients uses Carl Rasmussen''s minimize function using Polak-Ribiere line search, Split-Bregman uses an augmented Lagrangian / Bregman splitting approach, Barzilai-Borwein uses a stepsize-adjusted gradient method without descent guarantee.'), ...        
        arg({'outerZinit','InitialUpperBound'},0.05,[],'Initial upper bound.','guru',true),...
        arg({'outerGainit','InitialVariationalParam'},1,[],'Initial variational parameter.','guru',true), ...
    }, 'Solver options. The options for the Variational Bayes solver of glm-ie.'), ...
    arg({'continuousTargets','ContinuousTargets','Regression'}, false, [], 'Whether to use continuous targets. This allows to implement some kind of damped regression approach.'),...
    arg({'votingScheme','VotingScheme'},'1v1',{'1v1','1vR'},'Voting scheme. If multi-class classification is used, this determine how binary classifiers are arranged to solve the multi-class problem. 1v1 gets slow for large numbers of classes (as all pairs are tested), but can be more accurate than 1vR.'), ...
    arg({'verbosity','Verbosity'},0,uint32([0 2]),'Verbosity level. Set to 0=disable output, 1=show outer-loop output, 2=show inner-loop outputs, too.'));

[trials,targets,lambdas,type,priors,shape,scaling,includeBias,solverOptions,continuousTargets,votingScheme,verbosity] = arg_toworkspace(args);

% check if we need to handle multi-class classification by voting
classes = unique(targets);
if length(classes) > 2 && strcmp(type,'classification') && ~continuousTargets
    model = ml_trainvote(trials, targets, votingScheme, @ml_trainglm, @ml_predictgl, varargin{:});
elseif length(classes) == 1
    error('BCILAB:only_one_class','Your training data set has no trials for one of your classes; you need at least two classes to train a classifier.\n\nThe most likely reasons are that one of your target markers does not occur in the data, or that all your trials of a particular class are concentrated in a single short segment of your data (10 or 20 percent). The latter would be a problem with the experiment design.');
else
    % === pre-process data ===
    
    % determine featureshape and vectorize data if necessary 
    [featureShape,trials,vectorizeTrials] = determine_featureshape(trials,shape,false);
    nFeatures = prod(featureShape);  % nFeatures does not count the bias
    nTrials = numel(trials)/nFeatures;

    % apply data scaling
    sc_info = hlp_findscaling(trials,scaling);
    trials = hlp_applyscaling(trials,sc_info);

    % remap target labels to -1,+1 for use with the logistic link function
    if strcmp(type,'classification') && length(classes) == 2 && ~continuousTargets
        targets(targets==classes(1)) = -1;
        targets(targets==classes(2)) = +1;
    end

    % optionally add bias term
    if includeBias
        trials = [trials ones(size(trials,1),1)]; end    
    nWeights = size(trials,2);  % nWeights counts the bias
    
    % === set up data matrices for the solver ===
    
    % initialize data from given trials/targets
    [X,y,B,t] = deal([]);
    tau = {};                       % tau will be vertically concatenated by dli_wrap()
    G = {};                         % G will be concatenated at the end
    potentials = {};                % cell array of potential functions
    potentialArgs = {};             % cell array of cell arrays of extra arguments to potential functions
    potentialVars = [];             % number of variables accepted by each potential
    if strcmp(type,'regression')
        % linear regression
        X = trials;
        y = targets(:);
    elseif strcmp(type,'classification')
        % logistic regression
        B = trials;
        potentials = {@potLogistic};
        potentialArgs = {{}};
        potentialVars = nTrials;
        tau = {targets(:)};
        t = zeros(nTrials,1);
        G = {eye(nTrials)};
    else
        error('Unsupported problem type: %s',hlp_tostring(type));
    end
    
    % dummy weight vector so we can test whether the linear operators work
    w = zeros(nFeatures + includeBias,1);
    
    % count how many potentials we have for X and for B to make sure that there is at least one
    % for both sites (otherwise dli cannot handle it)
    num_X = ~isempty(X);
    num_B = ~isempty(B);
    for trm=fieldnames(priors)'
        term = priors.(trm{1});
        if ~strcmp(term.arg_selection,'none')
            if isfield(term,'appendToX') && term.appendToX
                num_X = num_X+1;
            else
                num_B = num_B+1;
            end
        end
    end
    
    % for each prior term, append appropriate matrices
    for trm=fieldnames(priors)'
        tname = trm{1};
        term = priors.(tname);
        type = term.arg_selection;
        if ~strcmp(type,'none')
            % --- process linear operator (note: needs to be in a separate function to keep @()'s clean) ---
            B_mat = [];
            
            if ischar(term.B)
                % parse operators in string form 
                % (we allow use of convenience variables named a,..,h to describe the shape of the features)
                try
                    [a,b,c,d,e,f,g,h] = size(reshape(w(1:nFeatures),featureShape)); %#ok<NASGU,ASGLU>
                    term.B = eval(term.B);
                catch e
                    error('The linear operator for prior term %s (%s, %s) seems to have a syntax error: %s',tname,type,char(term.B),hlp_handleerror(e));
                end
            elseif isnumeric(term.B)
                % parse operators in numeric form
                B_mat = term.B;
                term.B = @(x)B_mat*x;
            else
                error('Unsupported format for prior term %s (%s): %s',tname,type,hlp_tostring(term.B,1000));
            end
            
            % try to evaluate the operator on dummy weights; determine if it can accept weights in
            % the feature shape or whether we should to fall back to vectorized weights; also
            % get the output size of B
            opB = term.B;
            try
                opResult = opB(reshape(w(1:nFeatures),featureShape));
                term.B = @(x)opB(reshape(x(1:sum(nFeatures)),featureShape));
            catch e1
                try
                    opResult = opB(w(1:sum(nFeatures)));
                    term.B = @(x)opB(x(1:sum(nFeatures)));
                catch e2
                    error('The linear operator for prior term %s (%s, %s) yields and error when applied to weight vector w: %s\nIt also fails when applied to weight tensor w:%s',tname,type,char(term.B),hlp_handleerror(e2),hlp_handleerror(e1));
                end
            end
            nProjections = numel(opResult);
            
            % deduce actual operator matrix
            if isempty(B_mat)
                B_mat = operator_to_matrix(term.B,numel(w)); end
            
            % --- process remaining parameters ---
            
            % generate group matrix G if necessary
            if isempty(term.G)
                if size(opResult,1) == 1
                    % the output of G is a row vector: trivial groups
                    term.G = eye(nProjections);
                elseif size(opResult,1) == nProjections
                    % the output of G is a column vector: one group for all
                    term.G = ones(nProjections,1);
                else
                    % the output of G is a matrix or tensor: generate group matrix
                    groups = ones(size(opResult,1),1) * (1:(nProjections/size(opResult,1)));                    
                    for g=size(groups,2):-1:1
                        term.G(g,:) = vec(groups==g)'; end
                end
            elseif size(term.G,2) ~= nProjections
                error('The given group matrix must be of size [#groups x #features] where #features=%i, but G is of size %s',nProjections,hlp_tostring(size(G)));
            end
                
            nGroups = size(term.G,1);
            
            % sanity-check t (shift parameter)
            if isscalar(term.t)
                % replicate for each projection
                term.t = term.t*ones(nProjections,1);
            elseif numel(term.t) ~= nProjections
                error('The given t (shift) parameter of prior term %s (%s) has %s elements, but should have %s (after application of the linear operator).',tname,char(term.B),numel(term.t),nProjections);
            else
                term.t = term.t(:);
            end
            
            % sanity-check tau (scale parameter)
            if isscalar(term.tau)
                % replicate for each projection
                term.tau = term.tau*ones(nGroups,1);
            elseif term.tauSearch
                % generate search() object, with each value in tau replicated for each projection
                term.tau = search(cellfun(@(tau){tau*ones(nGroups,1)},num2cell(term.tau(:)')));
            elseif numel(term.tau) ~= nGroups
                error('The given tau (scale) parameter of prior term %s (%s) has %s elements, but should have %s (after application of the group matrix).',tname,char(term.B),numel(term.tau),nGroups);
            elseif strcmp(type,'Gaussian') && term.appendToX
                error('The prior term %s (%s) has a multi-valued tau term, but tau cannot be used if appendToX is set to true; you can disable appendToX or reset tau to its default to get this to work.',tname,char(term.B));
            else
                term.tau = term.tau(:);
            end
   
            % --- append to input data matrices
            
            % append B_mat and tau
            if strcmp(type,'Gaussian') && ((term.appendToX || num_X==0) && num_B>0)
                % append it to X/y instead of B/tau if so desired, or if X would otherwise be blank,
                % but not if B would be blank
                X = [X; B_mat]; %#ok<*AGROW>
                y = [y; term.tau(:)];
            else
                % append to B, G, t, tau
                B = [B; B_mat];
                G = [G; term.G];
                t = [t; term.t];
                tau{end+1} = term.tau;
                % append potentials
                potentialVars(end+1) = nProjections;
                switch type
                    case 'Laplace'
                        potentials{end+1} = @potLaplace;
                        potentialArgs{end+1} = {};
                    case 'Gaussian'
                        potentials{end+1} = @potGauss;
                        potentialArgs{end+1} = {};                        
                    case 'Logistic'
                        potentials{end+1} = @potLogistic;
                        potentialArgs{end+1} = {};
                    case 'StudentT'
                        potentials{end+1} = @potT;
                        potentialArgs{end+1} = {quickif(length(term.nu)>1,search(term.nu),term.nu)};
                    case 'Sech2'
                        potentials{end+1} = @potSech2;
                        potentialArgs{end+1} = {};
                    case 'ExpPow'
                        potentials{end+1} = @potExpPow;
                        potentialArgs{end+1} = {quickif(length(term.alpha)>1,search(term.alpha),term.alpha)};
                    otherwise
                        error('Unsupported distribution type requested: %s',type);
                end
            end
        end
    end
    
    % append a Gaussian prior if no Gaussian part is included
    if isempty(X)
        X = eye(nFeatures,nWeights);
        y = zeros(nFeatures,1);
    end
    
    % === generate options struct for the solver ===
    
    opts = solverOptions;
    % post-process outerMethod
    opts.outerVarOpts = solverOptions.outerMethod;
    opts.outerMethod = lower(solverOptions.outerMethod.arg_selection);
    % post-process innerVBpls
    for fn=fieldnames(solverOptions.innerVBpls)'
        opts.(fn{1}) = solverOptions.innerVBpls.(fn{1}); end
    opts.innerVBpls = hlp_rewrite(solverOptions.innerVBpls.arg_selection, 'Quasi-Newton','plsLBFGS', ...
        'Truncated Newton','plsTN', 'Backtracking Conjugate Gradients','plsCGBT', ...
        'Conjugate Gradients','plsCG', 'Split-Bregman','plsSB', 'Barzilai-Borwein','plsBB');
    % post-process verbosity
    opts.outerOutput = verbosity>0;
    opts.innerOutput = verbosity>1;
    if isfield(opts.innerVBpls,'SBga') && isempty(opts.innerVBpls.SBga)
        opts.innerVBpls = rmfield(opts.innerVBpls,'SBga'); end
    
    % === run inference ===
    
    if length(lambdas)>1
        lambdas = search(lambdas); end
    
    % build arguments for solver
    args = {X,y,lambdas,B,t,struct('funcs',{potentials},'args',{potentialArgs},'lengths',{potentialVars}),tau,opts,G};
    
    % perform evidence maximization if requested
    fprintf('\n');
    if is_search(hlp_flattensearch(args))
        if verbosity>0
            fprintf('Performing evidence maximization...\n'); end
        [bestIdx,allInputs,allOutputs] = utl_gridsearch('clauses',@dli_wrap,args{:}); %#ok<NASGU>
        args = allInputs{bestIdx};
        model.best_lambda = args{3};
        model.best_pot = args{6};
        model.best_tau = args{end-2};
    end
    
    % infer the model
    [nlZ,m,ga,b,z,zu,Q,T] = dli_wrap(args{:});
    
    % === finalize model ===
    model.w = m;                                    % posterior mean of weights
    model.zu = zu;                                  % posterior marginal variances of weights
    model.Q = Q;                                    % posterior covariance factors
    model.T = T;                                    % posterior covariance scale matrix
    model.z = z;                                    % posterior marginal variances of projections
    model.nlZ = nlZ;                                % negative log marginal likelihood
    model.ga = ga;                                  % optimal value of the variational width parameters
    model.b = b;                                    % optimal value of the variational position parameters
    
    model.type = type;
    model.classes = classes;                        % set of class labels in training data
    model.continuousTargets = continuousTargets;    % whether continuous target values were requested
    model.includeBias = includeBias;                % whether a bias is included in the model
    model.vectorizeTrials = vectorizeTrials;        % whether trials need to be vectorized first
    model.featureShape = featureShape;              % shape vector for features
    model.sc_info = sc_info;                        % overall scaling info    
end


% wrapper around dli() which has nlZ as first output and which assembles pots and tau from parts
function [nlZ,m,ga,b,z,zu,Q,T] = dli_wrap(X,y,s2,B,t,pots,taus,opts,G)
fprintf('.');
% construct tau and pot inputs from cell arrays
tau = vertcat(taus{:});
% build inputs for potCat    
potList = {};
for p=1:length(pots.funcs)
    potFunc = pots.funcs{p};
    potArgs = pots.args{p};
    potList{end+1} = @(s,varargin) potFunc(s,potArgs{:},varargin{:});
end
[potRanges{1:length(potList)}] = chopdeal(1:sum(pots.lengths),pots.lengths);
pot = @(s,varargin)potCat(s,varargin{:},potList,potRanges);
if isempty(potList)
    pot = @(varargin)[]; end
    
% invoke actual solver
[m,ga,b,z,zu,nlZ,Q,T] = dli(X,y,s2,B,t,pot,tau,opts,G);
nlZ = nlZ(end);


% classification
%   B              128x7              7168  double                       
%   G                0x0                 0  double                       
%   Q                7x7               392  double                       
%   T                7x7               392  double                       
%   X                6x7               160  double             sparse    
%   b              128x1              1024  double                       
%   ga             128x1              1024  double                       
%   m                7x1                56  double                       
%   nlZ              6x1                48  double                       
%   opts             1x1              2230  struct                       
%   p                1x1                 8  double                       
%   pot              1x1                32  function_handle              
%   potArgs          0x0                 0  cell                         
%   potFunc          1x1                32  function_handle              
%   potList          1x1               144  cell                         
%   potRanges        1x1              1136  cell                         
%   pots             1x1               792  struct                       
%   s2               1x1                 8  double                       
%   t              128x1              1024  double                       
%   tau            128x1              1024  double                       
%   taus             1x1              1136  cell                         
%   y                6x1                48  double                       
%   z              128x1              1024  double                       
%   zu               7x1                56  double   

% regression
%   B                6x7               160  double             sparse    
%   G                6x6               288  double                       
%   Q                7x7               392  double                       
%   T                7x7               392  double                       
%   X              128x7              7168  double                       
%   ans              1x2                16  double                       
%   b                6x1                48  double                       
%   ga               6x1                48  double                       
%   m                7x1                56  double                       
%   nlZ              1x1                 8  double                       
%   opts             1x1              2230  struct                       
%   p                1x1                 8  double                       
%   pot              1x1                32  function_handle              
%   potArgs          0x0                 0  cell                         
%   potFunc          1x1                32  function_handle              
%   potList          1x1               144  cell                         
%   potRanges        1x1               160  cell                         
%   pots             1x1               792  struct                       
%   s2               1x1                 8  double                       
%   t                6x1                48  double                       
%   tau              6x1                48  double                       
%   taus             1x1               160  cell                         
%   y              128x1              1024  double                       
%   z                6x1                48  double                       
%   zu               7x1                56  double   
%   

% >> pot = @(s,varargin) potCat(s,varargin{:},{@potT,@potGauss},{1:5,6:9});


% note: I can implement general-purpose evidence maximization quite easily, just by running
% utl_gridsearch with all model parameters, including noise cov exposed :)

%  X   [mxn]  measurement matrix or operator
%  y   [mx1]  measurement vector
%  s2  [1x1]  measurement variance
%  B   [qxn]  matrix or operator
%  pot        potential function handle or function name string from pot/pot*.m
%  tau [qx1]  scale parameters of the potentials
%  t [qx1]    offset parameters of the potentials
%  G [dxn] is a "grouping matrix" --> acts as sqrt(G*x^2), that is, the nonzeros in each column of G define
%     a separate group; there can be overlapping groups, of course (but what that means is another
%     question)    

% note: we use B in the following way:
% in the outer loop:
%   B*u
%   B'*u
%   size(B,2)
% in the posterior-mean calc:
%   mvm(B,P,ei)
% in the PLS solvers:
%   B*M
%   B'*M
%   M*B




% 
% % pre-process the data
% if strcmp(ptype,'classification')
%     classes = unique(targets);
%     if length(classes) > 2
%         % in the multi-class case we use the voter
%         model = ml_trainvote(trials, targets, '1v1', @ml_trainglm, @ml_predictglm, varargin{:},'shape',shape,'vectorize_trials',vectorize_trials);
%         return
%     elseif length(classes) == 1
%         error('BCILAB:only_one_class','Your training data set has no trials for one of your classes; you need at least two classes to train a classifier.\n\nThe most likely reasons are that one of your target markers does not occur in the data, or that all your trials of a particular class are concentrated in a single short segment of your data (10 or 20 percent). The latter would be a problem with the experiment design.');
%     else       
%         % optionally scale the data
%         sc_info = hlp_findscaling(trials,scaling);
%         trials = hlp_applyscaling(trials,sc_info);
%         % remap target labels to -1,+1
%         targets(targets==classes(1)) = -1;
%         targets(targets==classes(2)) = +1;
%     end
% elseif strcmp(ptype,'regression')
%     classes = [];
%     % scale the data
%     sc_info = hlp_findscaling(trials,scaling);
%     trials = hlp_applyscaling(trials,sc_info);
% else
%     error('Unrecognized problem type.');
% end
% 
% % rewrite arguments
% args.innerVBpls = hlp_rewrite(args.innerVBpls,'Quasi-Newton','plsLBFGS','Truncated Newton','plsTN','Backtracking Conjugate Gradients','plsCGBT','Conjugate Gradients','plsCG','Split-Bregman','plsSB','Barzilai-Borwein','plsBB');
% 
% % call setup function
% if nargout(setupfcn) == 5
%     [X,y,B,pot,tau] = setupfcn(trials,targets,shape,args);
%     G = [];
% else
%     [X,y,B,pot,tau,G] = setupfcn(trials,targets,shape,args);
% end
% 
% if length(lambdas) > 1
%     % empirically find lambda with best evidence
%     for k=length(lambdas):-1:1
%         [uinf,ga,b,z,nlZ(k),Q,T] = hlp_diskcache('predictivemodels',@dli,X,y,lambdas(k),B,pot,tau,rmfield(args,{'trials','targets','lambdas','ptype','scaling','setupfcn','shape','doinspect'}),G); end %#ok<NASGU,ASGLU>
%     model.lambda_search = nlZ;
%     model.lambda_best = lambdas(argmin(nlZ));
% else
%     model.lambda_best = lambdas;
% end
% 
% % run inference
% [uinf,ga,b,z,nlZ,Q,T] = hlp_diskcache('predictivemodels',@dli,X,y,model.lambda_best,B,pot,tau,rmfield(args,{'trials','targets','lambdas','ptype','scaling','setupfcn','shape','doinspect'}),G); %#ok<ASGLU>
% 
% % add misc meta-data to the model
% model.ptype = ptype;
% model.classes = classes;
% model.sc_info = sc_info;
% model.shape = shape;
% model.w = uinf;
% model.vectorize = vectorize_trials;


% note: I can implement general-purpose evidence maximization quite easily, just by running
% utl_gridsearch with all model parameters, including noise cov exposed :)

%  X   [mxn]  measurement matrix or operator
%  y   [mx1]  measurement vector
%  s2  [1x1]  measurement variance
%  B   [qxn]  matrix or operator
%  pot        potential function handle or function name string from pot/pot*.m
%  tau [qx1]  scale parameters of the potentials
%  t [qx1]    offset parameters of the potentials
%  G [dxn] is a "grouping matrix" --> acts as sqrt(G*x^2), that is, the nonzeros in each column of G define
%     a separate group; there can be overlapping groups, of course (but what that means is another
%     question)


