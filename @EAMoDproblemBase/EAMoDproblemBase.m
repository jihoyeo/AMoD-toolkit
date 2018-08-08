classdef EAMoDproblemBase < handle
    % EAMoDproblemBase Represents an electric AMoD problem using a network flow model
    %   The model of the electric AMoD system used here is described in the
    %   paper:
    %   F. Rossi, R. Iglesias, M. Alizadeh, and M. Pavone, “On the interaction
    %   between Autonomous Mobility-on-Demand systems and the power network:
    %   models and coordination algorithms,” in Robotics: Science and Systems,
    %   Pittsburgh, Pennsylvania, 2018
    
    methods
        function obj = EAMoDproblemBase(spec)
            % EAMoDproblemBase Constructs an EAMoDproblemBase object
            %   obj = EAMoDproblemBase(spec) where spec is an instance of
            %   EAMoDspec specifying the problem.
            %   See also EAMoDspec
            
            validateattributes(spec,{'EAMoDspec'},{'scalar'},mfilename,'spec',1);
            
            spec.ValidateSpec();
            obj.spec = spec;
            
            [obj.RouteTime,obj.RouteCharge,obj.RouteDistance,obj.Routes] = obj.BuildRoutes();
            
            obj.state_range = 1:obj.FindEndRebLocationci(obj.spec.C,obj.spec.N);
            obj.relax_range = (obj.FindEndRebLocationci(obj.spec.C,obj.spec.N) + 1):obj.StateSize;
            
            obj.decision_variables = DefineDecisionVariables(obj);
        end
        
        decision_vector_val = EvaluateDecisionVector(obj);        
        n_start_vehicles = ComputeNumberOfVehiclesAtStart(obj)
        n_end_vehicles = ComputeNumberOfVehiclesAtEnd(obj,varargin)        
        [total_cost_val, pax_cost_val, reb_cost_val,relax_cost_val] = EvaluateAMoDcost(obj,varargin)        
        final_vehicle_distribution = GetFinalVehicleDistribution(obj,varargin)
        [DepTimeHist, ArrivalTimeHist] = GetTravelTimesHistograms(obj,varargin);
        [ChargingVehicleHist,DischargingVehicleHist,PaxVehicleHist,RebVehicleHist,IdleVehicleHist,AllVehicleHist] = GetVehicleStateHistograms(obj,varargin)
        [objective_value,solver_time,diagnostics] = Solve(obj)
                
        % Ploting methods
        figure_handle = PlotRoadGraph(obj)
        figure_handle = PlotDeparturesAndArrivals(obj,varargin)
        figure_handle = PlotVehicleState(obj,params_plot,varargin)
        
        % Determine matrices for the linear program
        [f_cost,f_cost_pax,f_cost_reb,f_cost_relax] = CreateCostVector(obj)
        
        % Equality constraints for standard formulation
        [Aeq_PaxConservation, Beq_PaxConservation] = CreateEqualityConstraintMatrices_PaxConservation(obj)
        [Aeq_RebConservation, Beq_RebConservation] = CreateEqualityConstraintMatrices_RebConservation(obj)
        [Aeq_SourceConservation, Beq_SourceConservation] = CreateEqualityConstraintMatrices_SourceConservation(obj)
        [Aeq_SinkConservation, Beq_SinkConservation] = CreateEqualityConstraintMatrices_SinkConservation(obj)
        
        % Equality constraints for real-time formulation
        [Aeq_CustomerChargeConservation, Beq_CustomerChargeConservation] = CreateEqualityConstraintMatrices_CustomerChargeConservation(obj)
        
        % Inequality constraints
        [Ain_RoadCongestion, Bin_RoadCongestion] = CreateInequalityConstraintMatrices_RoadCongestion(obj)
        [Ain_ChargerCongestion, Bin_ChargerCongestion] = CreateInequalityConstraintMatrices_ChargerCongestion(obj)
        
        [lb_StateVector,ub_StateVector] = CreateStateVectorBounds(obj)
                            
        % State vector indexing functions
        function res = FindRoadLinkPtckij(obj,t,c,k,i,j)
            % FindRoadLinkPtckij Indexer for customer flow in road edges in the extended network
            if obj.use_real_time_formulation
                error('FindRoadLinkPtckij is undefined for real time formulation.');
            else
                res = obj.FindRoadLinkHelpertckij(t,c,k,i,j);
            end
        end
        
        function res = FindRoadLinkRtcij(obj,t,c,i,j)
            % FindRoadLinkRtcij Indexer for rebalancing flow in road edges in the extended network
            if obj.use_real_time_formulation
                res = obj.FindRoadLinkHelpertckij(t,c,1,i,j);
            else
                res = obj.FindRoadLinkPtckij(t,c,obj.spec.M + 1,i,j);
            end
        end
        
        function res = FindChargeLinkPtckl(obj,t,c,k,i)
            % FindChargeLinkPtckl Indexer for customer flow in charging edges in the extended network
            if obj.use_real_time_formulation
                error('FindChargeLinkPtckl is undefined for real time formulation.');
            else
                res = obj.FindChargeLinkHelpertckij(t,c,k,i);
            end
        end
        
        function res = FindChargeLinkRtcl(obj,t,c,i)
            % FindChargeLinkRtcl Indexer for rebalancing flow in charging edges in the extended network
            if obj.use_real_time_formulation
                res = obj.FindChargeLinkHelpertckij(t,c,1,i);
            else
                res = obj.FindChargeLinkPtckl(t,c,obj.spec.M+1,i);
            end
        end
        
        function res = FindDischargeLinkPtckl(obj,t,c,k,i)
            % FindDischargeLinkPtckl Indexer for customer flow in discharging edges in the extended network
            if obj.use_real_time_formulation
                error('FindDischargeLinkPtckl is undefined for real time formulation.');
            else
                res = obj.FindDischargeLinkHelpertckl(t,c,k,i);
            end
        end
        
        function res = FindDischargeLinkRtcl(obj,t,c,i)
            % FindDischargeLinkRtcl Indexer for rebalancing flow in discharging edges in the extended network
            if obj.use_real_time_formulation
                res = obj.FindDischargeLinkHelpertckl(t,c,1,i);
            else
                res = obj.FindDischargeLinkPtckl(t,c,obj.spec.M + 1,i);
            end
        end
        
        function res = FindPaxSourceChargecks(obj,c,k,s)
            % FindPaxSourceChargecks Indexer for sources at a given charge c going from source s to sink k
            res = obj.FindDischargeLinkRtcl(obj.spec.Thor,obj.spec.C,obj.spec.NumChargers) + obj.spec.TotNumSources*(c-1) + obj.spec.CumNumSourcesPerSink(k) + s;
        end
        
        function res = FindPaxSinkChargetck(obj,t,c,k)
            % FindPaxSinkChargetck Indexer for sinks k at a given charge c arriving at time t
            res = obj.FindPaxSourceChargecks(obj.spec.C,obj.spec.M,obj.spec.NumSourcesPerSink(end)) + obj.spec.C*obj.spec.M*(t-1) + obj.spec.M*(c-1) + k;
        end
        
        function res = FindEndRebLocationci(obj,c,i)
            % FindEndRebLocationci Indexer for final position of rebalancing vehicles
            res = obj.FindPaxSinkChargetck(obj.spec.Thor,obj.spec.C,obj.spec.M) + obj.spec.N*(c-1) + i;
        end
        
        % Constraint Indexers
        function res = FindEqPaxConservationtcki(obj,t,c,k,i)
            % FindEqPaxConservationtcki Indexer for customer flow conservation constraints
            res = obj.spec.N*obj.spec.M*obj.spec.C*(t - 1) + obj.spec.N*obj.spec.M*(c - 1) + obj.spec.N*(k - 1) + i;
        end
        
        function res = FindEqRebConservationtci(obj,t,c,i)
            % FindEqRebConservationtci Indexer for rebalancing flow conservation constraints
            res = obj.spec.N*obj.spec.C*(t - 1) + obj.spec.N*(c - 1) + i;
        end
        
        function res = FindEqSourceConservationks(obj,k,s)
            % FindEqSourceConservationks Indexer for source conservation constraints
            res = obj.spec.CumNumSourcesPerSink(k) + s;
        end
        
        function res = FindEqSinkConservationk(obj,k)
            % FindEqSinkConservationk Indexer for sink conservation constraints
            res = k;
        end
        
        function res = FindInRoadCongestiontij(obj,t,i,j)
            % FindInRoadCongestiontij Indexer for road congestion constraints
            res = obj.spec.E*(t - 1) + obj.spec.cumRoadNeighbors(i) + obj.spec.RoadNeighborCounter(i,j);
        end
        
        function res = FindInChargerCongestiontl(obj,t,l)
            % FindInChargerCongestiontl Indexer for charger congestion constraints
            res = obj.spec.NumChargers*(t-1) + l;
        end
        
        % The indexing for FindSourceRelaxks is different from
        % TVPowerBalancedFlowFinder_sinkbundle because we do not include
        % the power network and we do not include the congestion relaxation
        function res = FindSourceRelaxks(obj,k,s)
            % FindSourceRelaxks Indexer for constraints relaxing sources
            if obj.spec.sourcerelaxflag
                res = obj.FindEndRebLocationci(obj.spec.C,obj.spec.N) +  obj.spec.CumNumSourcesPerSink(k) + s;
            else
                res = nan;
            end
        end
        
        % Get methods for dependent properties
        function res = get.StateSize(obj)
            if obj.spec.sourcerelaxflag
                res = obj.FindSourceRelaxks(obj.spec.NumSinks,obj.spec.NumSourcesPerSink(obj.spec.NumSinks));
            else
                res = obj.FindEndRebLocationci(obj.spec.C,obj.spec.N);
            end
        end
        
        function res = get.num_passenger_flows(obj)
            if obj.use_real_time_formulation
                res = 0;
            else
                res = obj.spec.M;
            end
        end
    end
    
    properties (Dependent)
        StateSize % Number of elements in the problem's state vector
        num_passenger_flows % Number of passenger flows. Is equal to spec.M in the normal case and zero in the real-time formulation
    end
    
    properties
        use_real_time_formulation(1,1) logical = false % Flag to use real-time formulation
        verbose(1,1) logical = false % Flag for verbose output
        yalmip_settings(1,1) = sdpsettings() % Struct with YALMIP settings
    end
    
    properties (SetAccess = private, GetAccess = public)
        spec(1,1) EAMoDspec % Object of class EAMoDspec specifying the problem
                
        % For real-time formulation
        
        RouteTime(:,:)  double {mustBeNonnegative,mustBeReal,mustBeInteger}  % RouteTime(i,j) is the number of time-steps needed to go from i to j
        RouteCharge(:,:)  double {mustBeNonnegative,mustBeReal,mustBeInteger} % RouteCharge(i,j) is the number of charge units needed to go from i to j
        RouteDistance(:,:)  double {mustBeNonnegative,mustBeReal} % RouteDistance(i,j) is the distance in meters to go from i to j
        Routes(:,:) cell % Routes{i,j} is the route from i to j expresed as a vector of connected nodes that need to be traversed
    end
    
    properties (Access = private)
        % TODO: rename to optimization_variables
        decision_variables(1,1) % Struct with optimization variables
        state_range(1,:) double
        relax_range(1,:) double
    end
    
    methods (Access = private)
        [RouteTime,RouteCharge,RouteDistance,Routes] = BuildRoutes(obj)        
        A_charger_power_w = ComputeChargerPowerMatrixNew(obj)        
        decision_variables = DefineDecisionVariables(obj)
        [total_cost, pax_cost,reb_cost, relax_cost] = GetAMoDcost(obj,varargin)
        constraint_array = GetConstraintArray(obj)
        objective = GetObjective(obj)
        
        function res = FindRoadLinkHelpertckij(obj,t,c,k,i,j)
            res = (t-1)*(obj.spec.E*(obj.num_passenger_flows + 1)*(obj.spec.C) + 2*(obj.num_passenger_flows+1)*obj.spec.NumChargers*(obj.spec.C)) + (c-1)*obj.spec.E*(obj.num_passenger_flows+1) + (k-1)*obj.spec.E + (obj.spec.cumRoadNeighbors(i) + obj.spec.RoadNeighborCounter(i,j));
        end
        
        function res = FindChargeLinkHelpertckij(obj,t,c,k,i)
            res = obj.FindRoadLinkRtcij(t,obj.spec.C,obj.spec.N,obj.spec.RoadGraph{end}(end)) + obj.spec.NumChargers*(obj.num_passenger_flows + 1)*(c-1) + obj.spec.NumChargers*(k-1) + i;  %Here we index the charger directly (as opposed to the node hosting the charger)
        end
        
        function res = FindDischargeLinkHelpertckl(obj,t,c,k,i)
            res = obj.FindChargeLinkRtcl(t,obj.spec.C,obj.spec.NumChargers) + obj.spec.NumChargers*(obj.num_passenger_flows + 1)*(c-1) + obj.spec.NumChargers*(k-1) + i;
        end
    end
end