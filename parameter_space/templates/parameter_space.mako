<%!
  import os
  import glob
  import re
  import json
  from itertools import chain
  from routes import url_for

  prefix = url_for("/")
  path = os.getcwd()
  
%>
<%
  app_root = "config/plugins/visualizations/"+visualization_name+"/"
  
  ## list of string lines of input bio file
  data = ''.join(list(hda.datatype.dataprovider(
    hda, 
    'line', 
    strip_lines=True, 
    strip_newlines=True )))
  
  results = json.loads(data)
  
  # print(results.keys())
  ## [u'parameter_values', u'parameters', u'variables', u'results', u'states', u'parameter_bounds', u'type', u'thresholds']
  
  ## parssing of bio file format to python structures (later used in JS)
  vars =   [str(k) for k in results['variables']]
  params = [[str(k), results['parameter_bounds'][i][0], results['parameter_bounds'][i][1]] for i, k in enumerate(results['parameters'])]
  thrs =   dict({str(k) : results['thresholds'][i] for i, k in enumerate(results['variables'])}, 
                **{str(k) : results['parameter_bounds'][i] for i, k in enumerate(results['parameters'])})
  
  type = str(results['type'])
  states = {k['id']: k['bounds'] for k in results['states'] }
  params_val = results['parameter_values']
  results = {str(k['formula']): k['data'] for k in results['results'] }
  
%>
<html lan"en">
  
  <head>
    <title>Parameter Space</title>
  	<script src="https://d3js.org/d3.v4.js" charset="utf-8"></script>
  	<script type="text/javascript" charset="utf-8">
      // definition of functions used in bio files so there is no need to transorm them 
      function Hillm(x,t,n,b,a) {
        return a+(b-a)*(Math.pow(t,n)/(Math.pow(x,n)+Math.pow(t,n)));
      };
      hillm = Hillm;
      function Hillp(x,t,n,a,b) {
        return a+(b-a)*(Math.pow(x,n)/(Math.pow(x,n)+Math.pow(t,n)));
      };
      hillp = Hillp;
      function Approx(s,ramps) {
        if(s <= ramps[0][0]) return(ramps[0][1])
        if(s >= ramps[ramps.length-1][0]) return(ramps[ramps.length-1][1])
        for(var i = 1, len = ramps.length;  i < len; ++i) {
          a = ramps[i-1]
          b = ramps[i]
          if(s >= a[0] && s <= b[0]) return(a[1]+(s-a[0])/(b[0]-a[0])*(b[1]-a[1]))
        }
      }
      
      // creates one structure containing all data from result.json file for JS code
      window.bio = {'thrs': ${thrs}, 
                    'vars': ${vars}, 
                    'params': ${params}};
      window.result = {'type': "${type}", 
                       'states': ${states}, 
                       'params': ${params_val}, 
                       'map': ${results} };
      console.log(window.bio);
      console.log(window.result);
      
      Set.prototype.difference = function(setB) {
          var difference = new Set(this);
          for (var elem of setB) {
              difference.delete(elem);
          }
          return difference;
      };
      d3.selection.prototype.moveUp = function() {
          return this.each(function() {
              this.parentNode.appendChild(this);
          });
      };
      function parsing_to_string(x) {
        if(Object.values(x).length > 0) {
          var result = Number.parseFloat(Object.values(x)[0]).toFixed(2).toString();
          for(var i = 1; i < Object.values(x).length; ++i) {
            result += " "+Number.parseFloat(Object.values(x)[i]).toFixed(2).toString();
          }
          return result;
        } else return "";
      };
    </script>
  
    <!--meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1, maximum-scale=1"-->
    <style>
      body {
        background-color: white;
        margin: 0;
        font-family: sans-serif;
        font-size: 18px;
      }
      .containers {
        pointer-events: all;
      }
      #zoomObject_PS {
      }
      .interval {
        vector-effect: non-scaling-stroke; 
      }
      .loop {
        vector-effect: non-scaling-stroke; 
      }
      .transition { 
        vector-effect: non-scaling-stroke; 
      }
      .states {
        vector-effect: non-scaling-stroke; 
      }
      .axis {
        font-size: 15px;
      }
      .widget_panel {
        position: absolute;
        left: 560px;
        height: 100%;
        width: 230px;
        
      }
      #resetZoomBtn_PS {
        position: absolute;
        top: 10px;
      }
      #resetReachBtn_PS {
        position: absolute;
        top: 40px;
      }
      #infoPanel_PS {
        position: absolute;
        top: 70px;
        flex-grow: 1;
      }
      #x_axis_PS_div {
        position: absolute;
        top: 160px;
        width: 90px;
      }
      #y_axis_PS_div {
        position: absolute;
        top: 160px;
        width: 90px;
        left: 100px;
      }
      #slidecontainer_PS {
        position: absolute;
        top: 200px;
      }
      #formula_div {
        position: absolute;
        top: 550px;
      }
      
      #resetZoomBtn_SS {
        position: absolute;
        top: 650px;
      }
      #resetReachBtn_SS {
        position: absolute;
        top: 680px;
      }
      #infoPanel_SS {
        position: absolute;
        top: 710px;
        flex-grow: 1;
      }
      #x_axis_SS_div {
        position: absolute;
        top: 800px;
        width: 90px;
      }
      #y_axis_SS_div {
        position: absolute;
        top: 800px;
        width: 90px;
        left: 100px;
      }
      #slidecontainer_SS {
        position: absolute;
        top: 840px;
      }
    </style>
    
  </head>
  
  <body>
    <div class="widget_panel">
      <button id="resetZoomBtn_PS">Unzoom</button>
      <button id="resetReachBtn_PS">Deselect</button>
      <textarea id="infoPanel_PS" rows="${len(params)+2}" cols="35" wrap="off" disabled></textarea>
      <!-- dynamicly adds sliders with labels for parameters and variables (if more than 2 vars are present) in mako style -->
      <div id="x_axis_PS_div">
        X axis<br>
        <select name="xAxis" id="x_axis_PS" style="width:90px" required>
          % for val in [k[0] for k in params]+vars:
            % if val == params[0][0]:
              <option value="${val}" selected>${val}</option>
            % else:
              <option value="${val}">${val}</option>
            % endif
          % endfor
        </select>
      </div>
      <div id="y_axis_PS_div">
        Y axis<br>
        <select name="yAxis" id="y_axis_PS" style="width:90px" required>
          % for val in [k[0] for k in params]+vars:
            % if len(params) > 1 and val == params[1][0]:
              <option value="${val}" selected>${val}</option>
            % else:
              <option value="${val}">${val}</option>
            % endif
          % endfor
        </select>
      </div>
      <div id="slidecontainer_PS">
      <hr>
      % for val in params:
        <% 
        min_val  = float(val[1])
        max_val  = float(val[2])
        step_val = abs(max_val-min_val)*0.001
        %>
        % if val[0] == params[0][0] or val[0] == params[1][0]:
        <!--div id="slider_PS_${val[0]}_wrapper" hidden-->
        <div id="slider_PS_${val[0]}_wrapper">
        % else:
        <div id="slider_PS_${val[0]}_wrapper">
        % endif
          par. ${val[0]}: <span id="text_PS_${val[0]}"></span><br>
          <input type="range" min=${min_val} max=${max_val} value=${min_val} step=${step_val} class="slider" id="slider_PS_${val[0]}">
          <input type="checkbox" value="all" class="cb" id="checkbox_PS_${val[0]}" checked>whole
        </div>
      % endfor
      <hr>
      % for val in vars:
        <% 
        min_val  = min(map(float,thrs[val]))
        max_val  = max(map(float,thrs[val]))
        step_val = abs(max_val-min_val)*0.01
        %>
        <div id="slider_PS_${val}_wrapper">
          var. ${val}: <span id="text_PS_${val}"></span><br>
          <input type="range" min=${min_val} max=${max_val} value=${min_val} step=${step_val} class="slider" id="slider_PS_${val}">
          <input type="checkbox" value="all" class="cb" id="checkbox_PS_${val}" checked>whole
        </div>
      % endfor
      </div>
      <div id="formula_div">
        Property<br>
        <select id="formula" style="width:190px" required>
          % for key, val in enumerate(results.keys()):
            % if key == 0:
              <option value="${val}" selected>${val}</option>
            % else:
              <option value="${val}">${val}</option>
            % endif
          % endfor
        </select>
        Param<br>
        <select id="param_id" style="width:190px" required>
            <option value="all" selected>all</option>
          % for key, val in enumerate(params_val):
            <option value="${key}">${key}</option>
          % endfor
        </select>
        <hr>
      </div>
      <button id="resetZoomBtn_SS">Unzoom</button>
      <button id="resetReachBtn_SS">Deselect</button>
      <textarea id="infoPanel_SS" rows="${len(vars)+1}" cols="35" wrap="off" disabled></textarea>
      <div id="x_axis_SS_div">
        X axis<br>
        <select name="xAxis" id="x_axis_SS" style="width:90px" required>
          % for val in vars:
            % if val == vars[0]:
              <option value="${val}" selected>${val}</option>
            % else:
              <option value="${val}">${val}</option>
            % endif
          % endfor
        </select>
      </div>
      <div id="y_axis_SS_div">
        Y axis<br>
        <select name="yAxis" id="y_axis_SS" style="width:90px" required>
          % for val in vars:
            % if len(vars) > 1 and val == vars[1]:
              <option value="${val}" selected>${val}</option>
            % else:
              <option value="${val}">${val}</option>
            % endif
          % endfor
        </select>
      </div>
      <div id="slidecontainer_SS">
      <hr>
      % if len(vars) > 2 :
        % for val in vars:
          <% 
          min_val  = min(map(float,thrs[val]))
          max_val  = max(map(float,thrs[val]))
          step_val = abs(max_val-min_val)*0.01
          %>
          % if val == vars[0] or val == vars[1]:
          <div id="slider_SS_${val}_wrapper" hidden>
          % else:
          <div id="slider_SS_${val}_wrapper">
          % endif
            var. ${val}: <span id="text_SS_${val}"></span><br>
            <input type="range" min=${min_val} max=${max_val} value=${min_val} step=${step_val} class="slider" id="slider_SS_${val}">
          </div>
        % endfor
      % endif
      </div>
    </div>
    
    <script type="text/javascript" charset="utf-8">
   
var xDimPS = document.getElementById("x_axis_PS").value,
    yDimPS = document.getElementById("y_axis_PS").value,
    xDimPS_id = (window.bio.vars.includes(xDimPS) ? window.bio.vars.findIndex(x => x == xDimPS) : window.bio.params.findIndex(x => x[0] == xDimPS)),
    yDimPS_id = (window.bio.vars.includes(yDimPS) ? window.bio.vars.findIndex(x => x == yDimPS) : window.bio.params.findIndex(x => x[0] == yDimPS)),
    xDimSS = document.getElementById("x_axis_SS").value,
    yDimSS = document.getElementById("y_axis_SS").value,
    xDimSS_id = window.bio.vars.findIndex(x => x == xDimSS),
    yDimSS_id = window.bio.vars.findIndex(x => x == yDimSS),
    
    thrs = window.bio.thrs,
    formula = document.getElementById("formula").value,
    sel_result_data = window.result.map[formula],
    sel_result_data_transposed = (sel_result_data.length > 0 ? sel_result_data[0].map((col, i) => sel_result_data.map(row => row[i])) : []),
    param_bounds = [],
    var_bounds = [];

// initial parametric bounds are not limited (projection through all parametric dimensions)
window.bio.params.forEach(x => param_bounds.push(null));
// initial bounds of variables are not limited (projection through all dimensions)
window.bio.vars.forEach(x => var_bounds.push(null));

// iteratively adds event listener for variable sliders in PS (according to index)
% for key, val in enumerate(vars):
    (function(i,d) {
        d3.select("#text_PS_"+d).html(d3.select("#slider_PS_"+d).property("value"));
        
        d3.select("#slider_PS_"+d).on("input", function() {
            d3.select("#text_PS_"+d).html(this.value);
            if(! d3.select("#checkbox_PS_"+d).property("checked")) {
                var_bounds[i] = Number(d3.select("#slider_PS_"+d).property("value"));
                result_data_relevance()
                compute_projection()
                draw_PS()
                compute_statedata()
                draw_SS()
            }
        });
        d3.select('#checkbox_PS_'+d).on("change", function() {
            if(! d3.select("#checkbox_PS_"+d).property("checked")) {
                var_bounds[i] = Number(d3.select("#slider_PS_"+d).property("value"));
            } else {
                var_bounds[i] = null;
            }
            result_data_relevance()
            compute_projection()
            draw_PS()
            compute_statedata()
            draw_SS()
        });
    })(${key},"${val}");
% endfor

// iteratively adds event listener for parameter sliders in PS (according to index)
% for key, val in enumerate(params):
    (function(i,d) {
        d3.select("#text_PS_"+d[0]).html(d3.select("#slider_PS_"+d[0]).property("value"));
        
        d3.select("#slider_PS_"+d[0]).on("input", function() {
            d3.select("#text_PS_"+d[0]).html(this.value);
            if(! d3.select("#checkbox_PS_"+d[0]).property("checked")) {
                param_bounds[i] = Number(d3.select("#slider_PS_"+d[0]).property("value"));
                compute_projection()
                draw_PS()
            }
        });
        d3.select('#checkbox_PS_'+d[0]).on("change", function() {
            if(! d3.select("#checkbox_PS_"+d[0]).property("checked")) {
                param_bounds[i] = Number(d3.select("#slider_PS_"+d[0]).property("value"));
            } else {
                param_bounds[i] = null;
            }
            compute_projection()
            draw_PS()
        });
    })(${key},${val});
% endfor

// iteratively adds event listener for variable sliders in SS (according to index)
% if len(vars) > 2:
  % for key, val in enumerate(vars):
      (function(i,d) {
          d3.select("#text_SS_"+d).html(d3.select("#slider_SS_"+d).property("value"));
          
          d3.select("#slider_SS_"+d).on("input", function() {
              d3.select("#text_SS_"+d).html(this.value);
              
              compute_statedata()
              draw_SS()
          })
      })(${key},"${val}");
  % endfor
% endif
  
// event listener for change of selectected dimension for X axis in PS
d3.select("#x_axis_PS").on("change", function() {
  var other = d3.select("#y_axis_PS").property("value");
  if(this.value == other) {
    d3.select("#y_axis_PS").property('value',xDimPS);
    yDimPS = xDimPS;
  } else {
//    d3.select("#slider_"+xDimPS+"_wrapper").attr("hidden",null);
  }
  xDimPS = this.value;
//  d3.select("#slider_"+this.value+"_wrapper").attr("hidden","hidden");
  if(window.bio.vars.includes(xDimPS))  xDimPS_id = window.bio.vars.findIndex(x => x == xDimPS);
  else                                  xDimPS_id = window.bio.params.findIndex(x => x[0] == xDimPS);
  if(window.bio.vars.includes(yDimPS))  yDimPS_id = window.bio.vars.findIndex(x => x == yDimPS);
  else                                  yDimPS_id = window.bio.params.findIndex(x => x[0] == yDimPS);

  resettedZoom_PS()
  result_data_relevance()
  compute_projection()
  draw_PS()
});

// event listener for change of selectected dimension for Y axis in PS
d3.select("#y_axis_PS").on("change", function() {
  var other = d3.select("#x_axis_PS").property("value");
  if(this.value == other) {
    d3.select("#x_axis_PS").property('value',yDimPS);
    xDimPS = yDimPS;
  } else {
//    d3.select("#slider_PS_"+yDimPS+"_wrapper").attr("hidden",null);
  }
  yDimPS = this.value;
//  d3.select("#slider_PS_"+this.value+"_wrapper").attr("hidden","hidden");
  if(window.bio.vars.includes(xDimPS))  xDimPS_id = window.bio.vars.findIndex(x => x == xDimPS);
  else                                  xDimPS_id = window.bio.params.findIndex(x => x[0] == xDimPS);
  if(window.bio.vars.includes(yDimPS))  yDimPS_id = window.bio.vars.findIndex(x => x == yDimPS);
  else                                  yDimPS_id = window.bio.params.findIndex(x => x[0] == yDimPS);

  resettedZoom_PS()
  result_data_relevance()
  compute_projection()
  draw_PS()
});

// event listener for change of selectected dimension for X axis in SS
d3.select("#x_axis_SS").on("change", function() {
  var other = d3.select("#y_axis_SS").property("value");
  if(this.value == other) {
    d3.select("#y_axis_SS").property('value',xDimSS);
    yDimSS = xDimSS;
  } else {
    d3.select("#slider_SS_"+xDimSS+"_wrapper").attr("hidden",null);
  }
  xDimSS = this.value;
  d3.select("#slider_SS_"+this.value+"_wrapper").attr("hidden","hidden");
  
  xDimSS_id = window.bio.vars.findIndex(x => x == xDimSS)
  yDimSS_id = window.bio.vars.findIndex(x => x == yDimSS)

  resettedZoom_SS()
  compute_statedata()
  draw_SS()
});
// event listener for change of selectected dimension for Y axis in SS
d3.select("#y_axis_SS").on("change", function() {
  var other = d3.select("#x_axis_SS").property("value");
  if(this.value == other) {
    d3.select("#x_axis_SS").property('value',yDimSS);
    xDimSS = yDimSS;
  } else {
    d3.select("#slider_SS_"+yDimSS+"_wrapper").attr("hidden",null);
  }
  yDimSS = this.value;
  d3.select("#slider_SS_"+this.value+"_wrapper").attr("hidden","hidden");

  xDimSS_id = window.bio.vars.findIndex(x => x == xDimSS)
  yDimSS_id = window.bio.vars.findIndex(x => x == yDimSS)

  resettedZoom_SS()
  compute_statedata()
  draw_SS()
});

d3.select("#formula").on("change", function() {
  formula = d3.select("#formula").property("value");
    
  result_data_relevance()
  compute_projection()
  draw_PS()
  compute_statedata()
  draw_SS()
});

d3.select("#param_id").on("change", function() {
  
  compute_projection()
  draw_PS()
})

d3.select('#resetReachBtn_PS')
    .on("click", resettedClick_PS);
d3.select('#resetReachBtn_SS')
    .on("click", resettedClick_SS);

d3.select('#resetZoomBtn_PS')
    .on("click", resettedZoom_PS);
d3.select('#resetZoomBtn_SS')
    .on("click", resettedZoom_SS);
    
//###################################################    

var width = 550,
    height = 450,
    margin = { top: 10, right: 10, bottom: 50, left: 50 },
    arrowlen = 7,
    color = "transparent",
    reachColor = "rgb(65, 105, 225)", // "royalblue"
    neutral_col = "black",
    positive_col = "darkgreen",
    negative_col = "red",
    normalStrokeWidth = 1,
    hoverStrokeWidth = 4,
    transWidth = 2,
    selfloopWidth = 4,
    projdata = [],
    statedata = [],
    selectedStates = [],
    zoomObject_PS = d3.zoomIdentity,
    zoomObject_SS = d3.zoomIdentity;

// trans example = {
//   0:[0,1],
//   1:[0,3],
//   2:[3],
//   3:[3]
// };

var xScalePS = d3.scaleLinear()
      .domain([d3.min(thrs[xDimPS],parseFloat),
               d3.max(thrs[xDimPS],parseFloat)])
      .range([margin.left, width - margin.right]),
    xScaleSS = d3.scaleLinear()
      .domain([d3.min(thrs[xDimSS],parseFloat),
               d3.max(thrs[xDimSS],parseFloat)])
      .range([margin.left, width - margin.right])

var yScalePS = d3.scaleLinear()
      .domain([d3.min(thrs[yDimPS],parseFloat),
               d3.max(thrs[yDimPS],parseFloat)])
      .range([height - margin.bottom, margin.top]),
    yScaleSS = d3.scaleLinear()
      .domain([d3.min(thrs[yDimSS],parseFloat),
               d3.max(thrs[yDimSS],parseFloat)])
      .range([height - margin.bottom, margin.top])
      
var brushXPS = d3.brushX()
    .extent([[margin.left, 0], [width-margin.right, margin.bottom]])
    .on("end", brushedX_PS),
    
    brushYPS = d3.brushY()
    .extent([[-margin.left, margin.top], [0, height-margin.bottom]])
    .on("end", brushedY_PS),
    
    brushXSS = d3.brushX()
    .extent([[margin.left, 0], [width-margin.right, margin.bottom]])
    .on("end", brushedX_SS),
    
    brushYSS = d3.brushY()
    .extent([[-margin.left, margin.top], [0, height-margin.bottom]])
    .on("end", brushedY_SS)

var zoomPS = d3.zoom()
          //.scaleExtent([1, Infinity])
          //.translateExtent([[0,0],[width,height]])
          .on("zoom", zoomed_PS),
    zoomSS = d3.zoom()
          //.scaleExtent([1, Infinity])
          //.translateExtent([[0,0],[width,height]])
          .on("zoom", zoomed_SS)
          
var svgPS = d3.select("body").append("svg")
      .attr("width", width)
      .attr("height", height),
    svgSS = d3.select("body").append("svg")
      .attr("width", width)
      .attr("height", height)

var containerPS = svgPS.append("g")
        .attr("class", "containers")
        .attr("id","cont_ps")
        //.attr("transform", "translate("+(margin.left)+","+(margin.top)+")")
        .call(zoomPS),
    containerSS = svgSS.append("g")
        .attr("class", "containers")
        .attr("id","cont_ss")
        //.attr("transform", "translate("+(margin.left)+","+(margin.top)+")")
        .call(zoomSS)

var xLabelPS = svgPS.append("text")
      .attr("id", "xLabelPS")
      .attr("class", "label")
      .attr("x", width*0.5)
      .attr("y", height-10)
      .attr("stroke", "black")
      .text(function() { return xDimPS; }),
    xLabelSS = svgSS.append("text")
      .attr("id", "xlabelSS")
      .attr("class", "label")
      .attr("x", width*0.5)
      .attr("y", height-10)
      .attr("stroke", "black")
      .text(function() { return xDimSS; })
var yLabelPS = svgPS.append("text")
      .attr("id", "yLabelPS")
      .attr("class", "label")
      .attr("transform", "rotate(-90)")
      .attr("x", -height*0.5)
      .attr("y", 15)
      .attr("stroke", "black")
      .text(function() { return yDimPS; }),
    yLabelSS = svgSS.append("text")
      .attr("id", "yLabelSS")
      .attr("class", "label")
      .attr("transform", "rotate(-90)")
      .attr("x", -height*0.5)
      .attr("y", 15)
      .attr("stroke", "black")
      .text(function() { return yDimSS; })

var bottomPanelPS = svgPS.append("g")
    .attr("id", "bPanelPS")
    .attr("class", "panel")
    .attr("transform", "translate("+(0)+","+(height-margin.bottom)+")");
var xAxisPS = d3.axisBottom(xScalePS);
var gXPS = bottomPanelPS.append("g")
    .attr("id", "xAxisPS")
    .attr("class", "axis")
    .call(xAxisPS); // Create an axis component with d3.axisBottom
var gBXPS = bottomPanelPS.append("g")
    .attr("id", "xBrushPS")
    .attr("class", "brush")
    .call(brushXPS);
    
var leftPanelPS = svgPS.append("g")
    .attr("id", "lPanelPS")
    .attr("class", "panel")
    .attr("transform", "translate("+(margin.left)+","+(0)+")");
var yAxisPS = d3.axisLeft(yScalePS);
var gYPS = leftPanelPS.append("g")
    .attr("id", "yAxisPS")
    .attr("class", "axis")
    .call(yAxisPS); // Create an axis component with d3.axisLeft
var gBYPS = leftPanelPS.append("g")
    .attr("id", "xBrushPS")
    .attr("class", "brush")
    .call(brushYPS);

var bottomPanelSS = svgSS.append("g")
    .attr("id", "bPanelSS")
    .attr("class", "panel")
    .attr("transform", "translate("+(0)+","+(height-margin.bottom)+")");
var xAxisSS = d3.axisBottom(xScaleSS);
var gXSS = bottomPanelSS.append("g")
    .attr("id", "xAxisSS")
    .attr("class", "axis")
    .call(xAxisSS); // Create an axis component with d3.axisBottom
var gBXSS = bottomPanelSS.append("g")
    .attr("id", "xBrushSS")
    .attr("class", "brush")
    .call(brushXSS);
    
var leftPanelSS = svgSS.append("g")
    .attr("id", "lPanelSS")
    .attr("class", "panel")
    .attr("transform", "translate("+(margin.left)+","+(0)+")");
var yAxisSS = d3.axisLeft(yScaleSS);
var gYSS = leftPanelSS.append("g")
    .attr("id", "yAxisSS")
    .attr("class", "axis")
    .call(yAxisSS); // Create an axis component with d3.axisLeft
var gBYSS = leftPanelSS.append("g")
    .attr("id", "xBrushSS")
    .attr("class", "brush")
    .call(brushYSS);

result_data_relevance()
compute_projection()
draw_PS()

compute_statedata()
draw_SS()

// ################# definitions of functions #################

function result_data_relevance() {
  sel_result_data = window.result.map[formula];
  
  var data = []
  for(var r=0, len=sel_result_data.length; r<len; ++r) {
    var sid = Number(sel_result_data[r][0])
    var pid = Number(sel_result_data[r][1])
    
    var shown = (selectedStates.length == 0 ? true : selectedStates.includes(sid))
    var vid = 0
    while(shown && vid < var_bounds.length) {
      const bound = var_bounds[vid]
      if(bound !== null && (d3.min(window.result.states[sid][vid]) > bound || d3.max(window.result.states[sid][vid]) < bound)) shown = false
      vid++
    }
    if(shown) data.push([sid,pid])
  }
  sel_result_data = data
  sel_result_data_transposed = (sel_result_data.length > 0 ? sel_result_data[0].map((col, i) => sel_result_data.map(row => row[i])) : [])
}
    
function compute_projection() {
  projdata = [];
  var state_ids = [],
      param_ids = [],
      param_sets = [];

  if (sel_result_data_transposed.length > 0) {
    if (window.bio.vars.includes(xDimPS) || window.bio.vars.includes(yDimPS)) {
      state_ids = sel_result_data_transposed[0]
      param_ids = sel_result_data_transposed[1]
      param_sets = param_ids.map(x => window.result.params[x])
    } else {
      param_ids = [...new Set(sel_result_data_transposed[1])]
      param_sets = param_ids.map(x => window.result.params[x])
    }
    
    if(d3.select("#param_id").property("value") == "all") {
      
      for(var p=0, len=param_sets.length; p<len; ++p) {
        const param_id = param_ids[p];
        const param_set = param_sets[p];
        var data = [];
        for(var i=0, len2=param_set.length; i<len2; ++i) {
          var interval = param_set[i];
          var shown = true;
          var par_id = 0;
          while(shown && par_id < param_bounds.length) {
            const bound = param_bounds[par_id];
            if(bound !== null && (d3.min(interval[par_id]) > bound || d3.max(interval[par_id]) < bound)) shown = false;
            par_id++;
          }
          if(shown) data.push({
            x: (window.bio.vars.includes(xDimPS) ? window.result.states[state_ids[p]][xDimPS_id] : interval[xDimPS_id]),
            y: (window.bio.vars.includes(yDimPS) ? window.result.states[state_ids[p]][yDimPS_id] : interval[yDimPS_id])
          })
        }
        if(data.length > 0) {
          projdata.push({
            "data": data,
            "id": (window.bio.vars.includes(xDimPS) || window.bio.vars.includes(yDimPS) ? state_ids[p]+"-"+param_id : param_id),
            "cov": (window.bio.vars.includes(xDimPS) || window.bio.vars.includes(yDimPS) ? 1 : sel_result_data_transposed[1].filter( x => x == param_id ).length)
          })
        }
      }
    } else {
      const p = d3.select("#param_id").property("value");
      const param_set = window.result.params[p];
  
      var data = [];
      for(var i=0, len2=param_set.length; i<len2; ++i) {
        var interval = param_set[i];
        var shown = true;
        var par_id = 0;
        while(shown && par_id < param_bounds.length) {
          const bound = param_bounds[par_id];
          if(bound !== null && (interval[par_id][0] > bound || interval[par_id][1] < bound)) shown = false;
          par_id++;
        }
        if(shown) data.push({
          x: interval[xDimPS_id],
          y: interval[yDimPS_id],
        })
      }
      if(data.length > 0) {
        projdata.push({
          "data": data,
          "id"  : p,
          "cov" : sel_result_data_transposed[1].filter( x => x == p ).length
        })
      }
    }
  }
  //console.log(projdata);
}
function compute_statedata() {
  statedata = []
  const vars = window.bio.vars.filter(x => x != xDimSS && x != yDimSS)
  var state_ids = [...new Set(sel_result_data_transposed[0])]
  window.state_ids = state_ids
  
  for(var i=0, len=Object.values(window.result.states).length; i < len; ++i) {
    var id    = Number(Object.entries(window.result.states)[i][0])
    var state = Object.entries(window.result.states)[i][1]
    
    var shown = true
    var v = 0
    while(shown && v < vars.length) {
      const var_id = window.bio.vars.indexOf(vars[v])
      const thr = Number(d3.select("#slider_SS_"+vars[v]).property("value"))
      if(state[var_id][0] > thr || state[var_id][1] < thr) shown = false
      v++
    }
    
    if(shown) statedata.push({
      "x" : state[xDimSS_id][0],
      "y" : state[yDimSS_id][1],
      "x1": state[xDimSS_id][1],
      "y1": state[yDimSS_id][0],
      "id": id,
      "color": (state_ids.includes(id) ? reachColor : color)
    })
  }
}
//######### SS part for zooming ############
function update_axes_SS() {
  // Update axes labels according to selected diemnsions
  d3.select('#xLabelSS').text(xDimSS);
  d3.select('#yLabelSS').text(yDimSS);
  // Update scales according to selected diemnsions
  xScaleSS.domain([d3.min(thrs[xDimSS],parseFloat),
                   d3.max(thrs[xDimSS],parseFloat)])

  yScaleSS.domain([d3.min(thrs[yDimSS],parseFloat),
                   d3.max(thrs[yDimSS],parseFloat)])
  // Update an axis component according to selected dimensions
  xAxisSS = d3.axisBottom(xScaleSS);
  gXSS.call(xAxisSS);
  yAxisSS = d3.axisLeft(yScaleSS);
  gYSS.call(yAxisSS);
  // reset brushes
  gBXSS.call(brushXSS.move, null);
  gBYSS.call(brushYSS.move, null);
}
function resettedClick_SS() {
  selectedStates = []
  
  result_data_relevance()
  compute_projection()
  draw_PS()
  compute_statedata()
  draw_SS()
}
function resettedZoom_SS() {
  update_axes_SS()
  containerSS.transition()
      .duration(500)
      .call(zoomSS.transform, d3.zoomIdentity);
}
function zoomed_SS() {
  if(d3.event.transform) zoomObject_SS = d3.event.transform;
  x = zoomObject_SS.rescaleX(xScaleSS);
  y = zoomObject_SS.rescaleY(yScaleSS);
  
  d3.selectAll(".states")
    .attr("x", d => x(d.x))
    .attr("y", d => y(d.y))
    .attr("width", d => x(d.x1)-x(d.x))
    .attr("height", d => y(d.y1)-y(d.y))
  
  gXSS.call(xAxisSS.scale(x));
  gYSS.call(yAxisSS.scale(y));
  // reset brushes
  gBXSS.call(brushXSS.move, null);
  gBYSS.call(brushYSS.move, null);
}
function brushedX_SS() {
  if (!d3.event.sourceEvent) return; // Only transition after input.
  if (!d3.event.selection) return; // Ignore empty selections.
  var sel = d3.event.selection;
  var domain = sel.map(xAxisSS.scale().invert);
  
  scale = xScaleSS.copy().domain(domain);
  range = scale.range().map(x => zoomObject_SS.applyX(x));
  domain = range.map(scale.invert);
  xScaleSS.domain(domain);
  
  zoomed_SS();
}
function brushedY_SS() {
  if (!d3.event.sourceEvent) return; // Only transition after input.
  if (!d3.event.selection) return; // Ignore empty selections.
  var sel = d3.event.selection;
  var domain = sel.map(yAxisSS.scale().invert);
  
  scale = yScaleSS.copy().domain(domain.reverse());
  range = scale.range().map(y => zoomObject_SS.applyY(y));
  domain = range.map(scale.invert);
  yScaleSS.domain(domain);
  
  zoomed_SS();
}

//######### PS part for zooming ############
function update_axes_PS() {
  // Update axes labels according to selected diemnsions
  d3.select('#xLabelPS').text(xDimPS);
  d3.select('#yLabelPS').text(yDimPS);
  // Update scales according to selected diemnsions
  xScalePS.domain([d3.min(thrs[xDimPS],parseFloat),
                   d3.max(thrs[xDimPS],parseFloat)])

  yScalePS.domain([d3.min(thrs[yDimPS],parseFloat),
                   d3.max(thrs[yDimPS],parseFloat)])
  // Update an axis component according to selected dimensions
  xAxisPS = d3.axisBottom(xScalePS);
  gXPS.call(xAxisPS);
  yAxisPS = d3.axisLeft(yScalePS);
  gYPS.call(yAxisPS);
  // reset brushes
  gBXPS.call(brushXPS.move, null);
  gBYPS.call(brushYPS.move, null);
}
function resettedClick_PS() {
  compute_projection()
  draw_PS()
  compute_statedata()
  draw_SS()
}
function resettedZoom_PS() {
  update_axes_PS()
  containerPS.transition()
      .duration(500)
      .call(zoomPS.transform, d3.zoomIdentity);
}
function zoomed_PS() {
  if(d3.event.transform) zoomObject_PS = d3.event.transform;
  x = zoomObject_PS.rescaleX(xScalePS);
  y = zoomObject_PS.rescaleY(yScalePS);
  
  d3.selectAll(".interval")
  .attr("d", d => {
    var path = "";
    for(var i=0, len=d.data.length; i<len; ++i) {
      var r = d.data[i];
      path += " M"+x(r.x[0])+" "+y(r.y[0])+" H"+x(r.x[1])+" V"+y(r.y[1])+" H"+x(r.x[0])+" z"
    };
    return path;
  })
  
  gXPS.call(xAxisPS.scale(x));
  gYPS.call(yAxisPS.scale(y));
  // reset brushes
  gBXPS.call(brushXPS.move, null);
  gBYPS.call(brushYPS.move, null);
}
function brushedX_PS() {
  if (!d3.event.sourceEvent) return; // Only transition after input.
  if (!d3.event.selection) return; // Ignore empty selections.
  var sel = d3.event.selection;
  var domain = sel.map(xAxisPS.scale().invert);
  // TODO: set up brush.move for scale over some threshold (similar to zoom.scaleExtent([1, 100000]) ) to force it to resize along that threshold
  // TODO: implement own control over zoom extent because with embeded functions either it's not possible to move or unzoome after brush or
  //       it's possible to zoom out into a point
  
  scale = xScalePS.copy().domain(domain);
  range = scale.range().map(x => zoomObject_PS.applyX(x));
  domain = range.map(scale.invert);
  xScalePS.domain(domain);
  
  zoomed_PS();
}
function brushedY_PS() {
  if (!d3.event.sourceEvent) return; // Only transition after input.
  if (!d3.event.selection) return; // Ignore empty selections.
  var sel = d3.event.selection;
  var domain = sel.map(yAxisPS.scale().invert);
  
  scale = yScalePS.copy().domain(domain.reverse());
  range = scale.range().map(y => zoomObject_PS.applyY(y));
  domain = range.map(scale.invert);
  yScalePS.domain(domain);
  
  zoomed_PS();
}
function handleMouseOver_PS(d, i) {
  var div = document.getElementById("infoPanel_PS");
  var mouse = d3.mouse(this);
  mouse = [zoomObject_PS.rescaleX(xScalePS).invert(mouse[0]), zoomObject_PS.rescaleY(yScalePS).invert(mouse[1])];
  var p_count = 0,
      s_count = 0,
      content = "";
      
  if(d3.select(this).attr("class") == "interval") {
    for(var i=0, len=projdata.length; i < len; ++i) {
      var pset = projdata[i];
      for(var j=0, len2=pset.data.length; j < len2; ++j) {
        const par = pset.data[j];
        if(mouse[0] > par.x[0] && mouse[0] < par.x[1] && mouse[1] > par.y[0] && mouse[1] < par.y[1]) {
          p_count++;
          s_count += pset.cov;
          break;
        }
      }
    }
  }
  
  content += "States covered: "+s_count;
  content += "\nParametrisations covered: "+p_count;
  for(var v = 0, len = window.bio.params.length; v < len; ++v) {
    var key = window.bio.params[v];
    content += "\n"+key[0]+": "+(key[0] == xDimPS ? mouse[0].toFixed(4) : 
                                  (key[0] == yDimPS ? mouse[1].toFixed(4) : 
                                    (d3.select("#checkbox_PS_"+key[0]).property("checked") ? "["+key[1]+"-"+key[2]+"]" :
                                      d3.select("#slider_PS_"+key[0]).property("value"))));
  }
  
  div.value = content;
}
function handleMouseOut_PS(d, i) {
  var div = document.getElementById("infoPanel_PS");
  var p_count = 0,
      s_count = 0,
      content = "";
      
  content += "States covered: "+s_count;
  content += "\nParametrisations covered: "+p_count;
  for(var v = 0, len = window.bio.params.length; v < len; ++v) {
    var key = window.bio.params[v];
    content += "\n"+key[0]+": "+(key[0] == xDimPS ? "["+zoomObject_PS.rescaleX(xScalePS).domain()[0].toFixed(4)+"-"+zoomObject_PS.rescaleX(xScalePS).domain()[1].toFixed(4)+"]" : 
                                  (key[0] == yDimPS ? "["+zoomObject_PS.rescaleY(yScalePS).domain()[0].toFixed(4)+"-"+zoomObject_PS.rescaleY(yScalePS).domain()[1].toFixed(4)+"]" : 
                                    (d3.select("#checkbox_PS_"+key[0]).property("checked") ? "["+key[1]+"-"+key[2]+"]" :
                                      d3.select("#slider_PS_"+key[0]).property("value"))));
  }
  
  div.value = content;
}
function handleMouseClick_PS(d, i) {
  var mouse = d3.mouse(this)
  mouse = [Number(zoomObject_PS.rescaleX(xScalePS).invert(mouse[0])), Number(zoomObject_PS.rescaleY(yScalePS).invert(mouse[1]))]
  console.log(mouse[0]+" x "+mouse[1])
  //console.log(i+":"+d.id)
  
  var sel = d3.selectAll(".interval")
    .filter(x => {
      for(var i=0, len=x.data.length; i<len; ++i) {
        var r = x.data[i];
        // Y scale is inverted, therefore, we use the the higher threshold as the first one and the lower threshold as the second one
        if(mouse[0] > Number(r.x[0]) && mouse[0] < Number(r.x[1]) && mouse[1] > Number(r.y[1]) && mouse[1] < Number(r.y[0])) {
          return true
        }
      }
      return false
    }).remove()
  console.log(sel)
    
  //containerPS.selectAll(".interval").remove()
  //containerPS.selectAll(".interval").merge(sel)
  
  //d3.select("#zoomField_PS").moveUp();
}

function handleMouseOver_SS(d, i) {
  var div = document.getElementById("infoPanel_SS");
  var content = "";
    d3.select(this).attr("stroke-width", hoverStrokeWidth);
  
  content = ""+d3.select(this).attr("id")
  
  div.value = content;
}
function handleMouseOut_SS(d, i) {
    d3.select(this).attr("stroke-width", normalStrokeWidth);
}
function handleMouseClick_SS(d, i) {
  if(!selectedStates.includes(d.id)) {
    selectedStates.push(d.id)
  } else {
    selectedStates = selectedStates.filter(x => x != d.id)
  }
  result_data_relevance()
  compute_projection()
  draw_PS()
  compute_statedata()
  draw_SS()
}

function draw_PS() {
  containerPS.select("#zoomField_PS").remove()
  containerPS.selectAll(".interval").remove()
  
  containerPS.append("rect")
    .attr("id", "zoomField_PS")
    .attr("x", margin.left)
    .attr("y", margin.top)
    .attr("width", width-margin.right-margin.left)
    .attr("height", height-margin.bottom-margin.top)
    .attr("fill", "none")
    .on("click", handleMouseClick_PS)
    .on("mousemove", handleMouseOver_PS)
    .on("mouseout", handleMouseOut_PS);
  
  var cov_range = projdata.map(x => x.cov)
  opScale = d3.scaleLinear().domain([d3.min(cov_range),d3.max(cov_range)]).range([0.1,1]);
  
  containerPS.selectAll(".interval")
    .data(projdata)
    .enter()
    .append("path")
    .attr("class", "interval")
    .attr("id", d => d.id)
    .attr("d", d => {
      var path = "";
      for(var i=0, len=d.data.length; i<len; ++i) {
        var r = d.data[i];
        // Y scale is inverted, therefore, we use the the higher threshold as the first one and the lower threshold as the second one
        path += " M"+zoomObject_PS.rescaleX(xScalePS)(r.x[0])+","+zoomObject_PS.rescaleY(yScalePS)(r.y[1])+" H"+zoomObject_PS.rescaleX(xScalePS)(r.x[1])+" V"+zoomObject_PS.rescaleY(yScalePS)(r.y[0])+" H"+zoomObject_PS.rescaleX(xScalePS)(r.x[0])
      }
      return path;
    })
    .attr("fill", reachColor)
    .attr("fill-opacity", d => ""+(projdata.length == 1 ? 1 : opScale(d.cov)))
    .attr("stroke", "none")
    .attr("stroke-width", normalStrokeWidth)
    .attr("pointed", false)
    .on("click", handleMouseClick_PS)
    .on("mousemove", handleMouseOver_PS)
    .on("mouseout", handleMouseOut_PS)
}

function draw_SS() {
  containerSS.select("#zoomField_SS").remove()
  containerSS.selectAll(".states").remove()
  
  containerSS.append("rect")
    .attr("id", "zoomField_SS")
    .attr("x", margin.left)
    .attr("y", margin.top)
    .attr("width", width-margin.right-margin.left)
    .attr("height", height-margin.bottom-margin.top)
    .attr("fill", "none")
    .on("click", handleMouseClick_SS)
    .on("mousemove", handleMouseOver_SS)
    .on("mouseout", handleMouseOut_SS);
  
  containerSS.selectAll(".states")
    .data(Object.values(statedata))
    .enter()
    .append("rect")
    .attr("class", "states")
    .attr("id", d => "s"+d.id)
    .attr("x", d => zoomObject_SS.rescaleX(xScaleSS)(d.x))
    .attr("y", d => zoomObject_SS.rescaleY(yScaleSS)(d.y))
    .attr("width", d => zoomObject_SS.rescaleX(xScaleSS)(d.x1)-zoomObject_SS.rescaleX(xScaleSS)(d.x))
    .attr("height", d => zoomObject_SS.rescaleY(yScaleSS)(d.y1)-zoomObject_SS.rescaleY(yScaleSS)(d.y))
    .attr("fill", d => d.color)
    .attr("stroke", "black")
    .attr("stroke-width", normalStrokeWidth)
    .attr("pointed", false)
    .on("click", handleMouseClick_SS)
    .on("mouseover", handleMouseOver_SS)
    .on("mouseout", handleMouseOut_SS)
}

    </script>
  </body>

</html>
