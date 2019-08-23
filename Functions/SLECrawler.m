function [SLE_final] = SLECrawler(LFP_filtered, eventTimes, frequency, LED, onsetDelay, offsetDelay, locs_spike, troubleshooting, durationOnsetBaseline, durationOffsetBaseline)
%'SLE Crawl' is a retired function that previously detected ictal event
%onset/offset.
%   You upload 1) bandpass filtered LFP data to analyze, 2) the times
%   where all the SLEs (aka ictal events) roughly occur to the nearest 0.5
%   sec, 3) the frequency of the sampling rate. The slecrawl function will
%   then detect the exact onset and offset as Michael Chang would mark the
%   ictal events. Michael determines the valley before the peak (sentinel
%   spike) to be the seizure onset and the point where all spiking activity
%   (power) ends to be the offset. This function can also determine if the
%   SLE is light-triggered and also ensures that the last spike is not  
%   induced by a light pulse or an artifact (because it's using locs_spike). 
%   Author: Michael Chang (michael.chang@live.ca)
%   Additional Notes: The default onset delay is 130 ms (or 100 ms after a
%   30 ms light pulse). The threshold for offset detection is
%   'meanOffsetBaseline/2'  SLE onset where spike prominience > 1/3 the
%   maximum amplitude of the "onset context".

  
%% Default values, if frequenct is not specified 
if nargin<3
    frequency = 10000;      % 10kHz is default sampling frequency   
    LED = [];               %No LED input
    onsetDelay = 0.13;      % seconds after light pulse onset to be considered triggered
    offsetDelay = 1.5;      % seconds the event offset follows light pulse to be considered associated
    troubleshooting = [];    % plot onset and offset detections
    durationOnsetBaseline = 1.0;     %sec (context to analyze for finding the onset)
    durationOffsetBaseline = 1.5;     %sec (context to analyze for finding the offset)        
end

if nargin<8
    troubleshooting = [];    % plot onset and offset detections
    durationOnsetBaseline = 1.0;     %sec (context to analyze for finding the onset)
    durationOffsetBaseline = 1.5;     %sec (context to analyze for finding the offset)    
end

if nargin<9    
    durationOnsetBaseline = 1.0;     %sec (context to analyze for finding the onset)
    durationOffsetBaseline = 1.5;     %sec (context to analyze for finding the offset)
end

%Set the duration of Offset Baseline to calculate the offset threshold (meanBaseline/2)
if durationOffsetBaseline >= 1.5
    calculateMeanOffsetBaseline = 1.5;    %sec (mean baseline value) | Note: should be smaller than duration
else
    calculateMeanOffsetBaseline = durationOffsetBaseline;
end


%create time vector
t = (0:(length(LFP_filtered)- 1))/frequency;
t = t';

% Find Light pulse
if LED
    [P] = pulse_seq(LED);   %determine location of light pulses     

    %Find range of time when light pulse has potential to trigger an event,
    clear lightTriggeredRange lightTriggeredZone
    for i = 1:numel(P.range(:,1))
        lightTriggeredOnsetRange = (P.range(i,1):P.range(i,1)+(onsetDelay*frequency));
        lightTriggeredOnsetZone{i} = lightTriggeredOnsetRange; 
        lightTriggeredOffsetRange = (P.range(i,1):P.range(i,1)+(offsetDelay*frequency));
        lightTriggeredOffsetZone{i} = lightTriggeredOffsetRange; 
    end

    %Combine all the ranges where light triggered events occur into one array
    lightTriggeredOnsetZones = cat(2, lightTriggeredOnsetZone{:});  %2 is vertcat
    lightTriggeredOffsetZones = cat(2, lightTriggeredOffsetZone{:});  %2 is vertcat
    
    %% remove spiking due to light pulse (from array of prominient spikes)    
    locs_spike_replicated = locs_spike(:,1);     %replicate array          
   
    for i = 1:numel(locs_spike_replicated)
        if intersect(locs_spike_replicated(i), lightTriggeredOffsetZones)
            locs_spike_replicated(i)=-1;
        end
    end
        
    %make index to indicate if spikes are triggered by light pulses
    locs_spike (:,2) = locs_spike_replicated > 0;   %if index is 0, means spike triggered by light    
end

if troubleshooting       
    %% Creating powerpoint slide
    isOpen  = exportToPPTX();
        if ~isempty(isOpen)
            % If PowerPoint already started, then close first and then open a new one
            exportToPPTX('close');
        end

    exportToPPTX('new','Dimensions',[12 6], ...
        'Title','Epileptiform Event Detector V4.0', ...
        'Author','Michael Chang', ...
        'Subject','Automatically generated PPTX file', ...
        'Comments','This file has been automatically generated by exportToPPTX');

    exportToPPTX('addslide');
    exportToPPTX('addtext', 'Troubleshooting: Epileptiform Events detected', 'Position',[2 1 8 2],...
                 'Horiz','center', 'Vert','middle', 'FontSize', 36);
    exportToPPTX('addtext', 'troubleshooting', 'Position',[3 3 6 2],...
                 'Horiz','center', 'Vert','middle', 'FontSize', 20);
    exportToPPTX('addtext', 'By: Michael Chang and Christopher Lucasius', 'Position',[4 4 4 2],...
                 'Horiz','center', 'Vert','middle', 'FontSize', 20);     

    exportToPPTX('addslide');
    exportToPPTX('addtext', 'Legend', 'Position',[0 0 4 1],...
                 'Horiz','left', 'Vert','middle', 'FontSize', 24);
    exportToPPTX('addtext', 'Epileptiform spike is average + 6*SD of the baseline', 'Position',[0 1 6 1],...
                 'Horiz','left', 'Vert','middle', 'FontSize', 14);
    exportToPPTX('addtext', 'Artifacts are average + 100*SD', 'Position',[0 2 5 1],...
                 'Horiz','left', 'Vert','middle', 'FontSize', 14);
    exportToPPTX('addtext', 'SLE onset is the first peak in power (minimum 1/3 of the max amplitude spike)', 'Position',[0 3 5 1],...
                 'Horiz','left', 'Vert','middle', 'FontSize', 14);
    exportToPPTX('addtext', 'SLE offset is when power returns below baseline/2', 'Position',[0 4 5 1],...
                 'Horiz','left', 'Vert','middle', 'FontSize', 14);
    exportToPPTX('addtext', 'Note: The event have only been shifted alone the y-axis to start at position 0', 'Position',[0 5 5 1],...
                 'Horiz','left', 'Vert','middle', 'FontSize', 16);      
end
    
%% Processing the data to extract features to determine the onset/offset
%Derivative of the filtered data (absolute value)
DiffLFP_filtered = abs(diff(LFP_filtered));     %2nd derived signal

%Power of the derivative of the filtered data (absolute values)
powerFeature = (DiffLFP_filtered).^2;                     %3rd derived signal

%Lowpass butter filter [2 Hz], to scan for offset
fc = 2; % Cut off frequency
[b,a] = butter(2,fc/(frequency/2)); %Butterworth filter of order 2
powerFeatureLowPassFiltered2 = filtfilt(b,a,powerFeature); %filtered signal

%Lowpass butter filter [25 Hz], to scan for onset
fc = 25; % Cut off frequency
[b,a] = butter(2,fc/(frequency/2)); %Butterworth filter of order 2
powerFeatureLowPassFiltered25 = filtfilt(b,a,powerFeature); %filtered signal

%% Absolute Values for testing
%Absolute value of the filtered data
AbsLFP_filtered = abs(LFP_filtered);            %Derived signal

%Power of the Absolute signal 
powerFeatureAbs = (AbsLFP_filtered).^2;       %3rd derived signal

%Lowpass butter filter [2 Hz], to scan for offset
fc = 2; % Cut off frequency
[b,a] = butter(2,fc/(frequency/2)); %Butterworth filter of order 2
powerFeatureLowPassFilteredAbs2 = filtfilt(b,a,powerFeatureAbs); %filtered power signal of derivative

% %Lowpass butter filter [25 Hz], to scan for onset
% fc = 25; % Cut off frequency
% [b,a] = butter(2,fc/(frequency/2)); %Butterworth filter of order 2
% powerFeatureLowPassFilteredAbs25 = filtfilt(b,a,powerFeatureAbs); %filtered power signal of derivative

%% Scanning Low-Pass Filtered Power signal for more accurate onset/offset times
%Preallocating for speed
SLEonset_final = zeros (size(eventTimes,1), 1);
SLEoffset_final = zeros (size(eventTimes,1), 1);
SLEoffset_final_Abs = zeros (size(eventTimes,1), 1);

for i = 1:size(eventTimes,1)
    %Putative SLE onset and offset times  
    onsetSLE = int64(eventTimes(i,1)*frequency);   %convert into a position
    offsetSLE = int64(eventTimes(i,2)*frequency);  %convert into a position

    %Baseline adjacent to SLE
    onsetBaselineStart = (onsetSLE-(durationOnsetBaseline*frequency));
    onsetBaselineEnd = (onsetSLE+(0.5*frequency));
    offsetBaselineStart = (offsetSLE-(0.5*frequency));
    offsetBaselineEnd = (offsetSLE+(durationOffsetBaseline*frequency));

    %Range of LFP to scan for onset
    if onsetBaselineStart > 0        
        onsetContext = int64(onsetBaselineStart:onsetBaselineEnd);
    else
        onsetContext = int64(1:onsetBaselineEnd);
    end

    %Range of LFP to scan for offset
    if offsetBaselineEnd < numel(powerFeatureLowPassFiltered2)  %note this is a power feature of the derivative signal, which has one less point than the Abs values
        offsetContext = int64(offsetBaselineStart:offsetBaselineEnd); 
    else
        offsetContext = int64(offsetBaselineStart:numel(powerFeatureLowPassFiltered2));
    end

    %Locating the onset time
    prominence = max(powerFeatureLowPassFiltered25(onsetContext))/3; %SLE onset where spike prominience > 1/3 the maximum amplitude
    [~, onset_locs] = findpeaks(powerFeatureLowPassFiltered25(onsetContext), 'MinPeakProminence', prominence);     
    if isempty(onset_locs)
        [~, peakIndex] = max(powerFeatureLowPassFiltered25(onsetContext));
        SLEonset_final(i,1) = t(onsetContext(peakIndex)); %The point with maximum power is the onset   
    else
        SLEonset_final(i,1) = t(onsetContext(onset_locs(1))); %The onset time, the first spike (increase in power) is the onset   
    end

    %Locating the offset time    
%     if offsetContext > 1.5*frequency %hard-code, duration of baseline to calculate offset threshold
%         meanOffsetBaseline = mean(powerFeatureLowPassFiltered2(offsetContext(1:1.5*frequency))); %Mean baseline of the first 1.5 s
%     else
%         meanOffsetBaseline = mean(powerFeatureLowPassFiltered2(offsetContext)); %Mean baseline of whatever remains
%     end    

    %Make vector and center it
    vectorOffsetContext = powerFeatureLowPassFiltered2(offsetContext);
    center = min(vectorOffsetContext);
    vectorOffsetContextCentered = powerFeatureLowPassFiltered2(offsetContext)-center;

    %Locating the offset time - using derivative values
    meanOffsetBaseline = mean(vectorOffsetContextCentered); %Mean baseline of context
    OffsetLocation = vectorOffsetContextCentered > meanOffsetBaseline/2; 
    offset_loc = find(OffsetLocation, 1, 'last'); %Last point is the index for the offset location    
    offsetSLE_2 = (offsetContext(offset_loc));  %detecting the new offset location         
    SLEoffset_final(i,1) = t(offsetSLE_2);
    
    %Locating the offset time - using absolute value signal  | Note: you
    %don't have to center the absolute values, they are typically already
    %centered.
    meanOffsetAbsBaseline = mean(powerFeatureLowPassFilteredAbs2(offsetContext)); %Mean baseline of offset context
    OffsetLocationAbs = powerFeatureLowPassFilteredAbs2(offsetContext) > meanOffsetAbsBaseline/2; 
    offset_loc_Abs = find(OffsetLocationAbs, 1, 'last'); %Last point is the index for the offset location    
    offsetSLE_2_Abs = (offsetContext(offset_loc_Abs));  %detecting the new offset location         
    SLEoffset_final_Abs(i,1) = t(offsetSLE_2_Abs);

    if LED 
        %make sure last spike is not light triggered
        lastBurstEvent = offsetSLE:offsetSLE_2; %the duration of the last burst, defined as putative detected offset, and crawler's detected offset
        lightTriggered = intersect(lastBurstEvent, lightTriggeredOffsetZones); %check if last burst event is due to a light trigger
        if lightTriggered %if it is light triggered, find last spike that is not light-triggered (new SLE offset)
            %find index of new SLE offset            
            offsetIndex = find(locs_spike(:,1) == int64(eventTimes(i,2)*frequency)); %find the preceding spike, using data from previous 'detectEvent function' in abs LFP
            precedingOffsetIndex = find(flipud(locs_spike(1:offsetIndex, 2))==1,1);        % Thomas flipped the array and looked for the first point where spike was not light-triggered; consider using the while-loop or for-loop backwards
            if isempty(precedingOffsetIndex)    %if the last spike can only be due to a light pulse; then it's not a SLE, break from this iteration
                SLEoffset_final(i,1) = -1;  %This is considered to be an artifact and will be removed; it is a spike with all preceding spikes due to light                
            else                
                newOffsetIndex = offsetIndex-(precedingOffsetIndex-1);  %subtract 1 because you're subtracting indices
                offsetSLE = int64(locs_spike(newOffsetIndex));  %approximate position of last spike

                %New range of LFP (context) to scan for the offset
                offsetBaselineStart = (offsetSLE-(0.5*frequency));  %SLE "context" (start of post-ictal baseline)
                offsetBaselineEnd = (offsetSLE+(durationOffsetBaseline*frequency));  %SLE "context" (end of post-ictal baseline)

                if offsetBaselineEnd < numel(powerFeatureLowPassFiltered2)
                    offsetContext = int64(offsetBaselineStart:offsetBaselineEnd); 
                else
                    offsetContext = int64(offsetBaselineStart:numel(powerFeatureLowPassFiltered2)); %SLE "context" (end of post-ictal baseline), end of recording, cut the SLE short
                end                                 

                %Locating the new offset time  - using the derivative signal  
                %Make vector and center it
                vectorOffsetContext = powerFeatureLowPassFiltered2(offsetContext);
                center = min(vectorOffsetContext);
                vectorOffsetContextCentered = powerFeatureLowPassFiltered2(offsetContext)-center;
                
                if numel(offsetContext) > (calculateMeanOffsetBaseline*frequency)
                    meanOffsetAbsBaseline = mean(vectorOffsetContextCentered(1:calculateMeanOffsetBaseline*frequency)); %Mean baseline of the first 1.5 s                    
                else
                    meanOffsetAbsBaseline = mean(vectorOffsetContextCentered); %Mean baseline calculated from whatever context there is                    
                end                 
                OffsetLocation = vectorOffsetContextCentered > meanOffsetBaseline/2; 
                offset_loc = find(OffsetLocation, 1, 'last'); %Last point (index) is the offset     
                if offset_loc
                    SLEoffset_final(i,1) = t(offsetContext(offset_loc)); %store the detected new offset time             
                else
                    SLEoffset_final(i,1) = t(offsetContext(numel(OffsetLocation)));  %If the signal never returns to the threshold (meanbaseline/2), then take the last point as the offset.
                end

                %Locating the offset time - using absolute value signal | Don't need to center
                if numel(offsetContext) > (calculateMeanOffsetBaseline*frequency)
                    meanOffsetAbsBaseline = mean(powerFeatureLowPassFilteredAbs2(offsetContext(1:calculateMeanOffsetBaseline*frequency))); %Mean baseline of the first 1.5 s
                else
                    meanOffsetAbsBaseline = mean(powerFeatureLowPassFilteredAbs2(offsetContext)); %Mean baseline calculated from whatever context there is
                end                                    
                OffsetLocationAbs = powerFeatureLowPassFilteredAbs2(offsetContext) > meanOffsetAbsBaseline/2; 
                offset_loc_Abs = find(OffsetLocationAbs, 1, 'last'); %Last point is the index for the offset location                    
                if offset_loc_Abs
                    offsetSLE_2_Abs = (offsetContext(offset_loc_Abs));  %detecting the new offset location             
                else
                    offsetSLE_2_Abs = (offsetContext(numel(OffsetLocationAbs)));  %In case the signal never returns to the threshold (meanbaseline/2), then take the last point as the offset.                    
                end                
                         
                SLEoffset_final_Abs(i,1) = t(offsetSLE_2_Abs);  %Store time of the new offset location
            end
        end
    end
        
    %% plotting the onset and offsets detected     
    if troubleshooting      
%        
%     %Plot onset detection
%     figHandle = figure;
%     set(gcf,'NumberTitle','off', 'color', 'w'); %don't show the figure number
%     set(gcf,'Name', sprintf ('SLE onset #%d', i)); %select the name you want
%     set(gcf, 'Position', get(0, 'Screensize'));   
%     subplot (2,1,1)
%     plot(t(onsetContext),LFP_filtered(onsetContext))
%     hold on
%     plot(t(onsetSLE), LFP_filtered(onsetSLE), 'x', 'color', 'red', 'MarkerSize', 12)  %initial (rough) detection
%     plot(SLEonset_final(i,1), LFP_filtered(onsetContext(onset_locs(1))), 'o', 'color', 'black', 'MarkerSize', 14)   %Detected onset point 
%     plot(t(onsetContext(onset_locs)), LFP_filtered(onsetContext(onset_locs)), '*', 'color', 'green', 'MarkerSize', 14)    %All potential detected onset points
%     
%     plot(t(onsetContext), LED(onsetContext)/8)
%     %Labels
%     title (sprintf('Event onset #%d, LFP Bandpass Filtered (1-100 Hz)', i));
%     ylabel ('mV');
%     xlabel ('Time (sec)');
%     
%     subplot (2,1,2)
%     plot(t(onsetContext), powerFeatureLowPassFiltered25(onsetContext))
%     hold on
%     plot(t(onsetSLE), powerFeatureLowPassFiltered25(onsetSLE), 'x', 'color', 'red', 'MarkerSize', 12)     %initial (rough) detection
%     plot(SLEonset_final(i,1), powerFeatureLowPassFiltered25(onsetContext(onset_locs(1))), 'o', 'color', 'black', 'MarkerSize', 14)    %Detected onset point 
%     plot(t(onsetContext(onset_locs)), powerFeatureLowPassFiltered25(onsetContext(onset_locs)), '*', 'color', 'green', 'MarkerSize', 14)    %All potential detected points
%     %Labels
%     title ('Power, Low Pass Filtered (25 Hz)');
%     ylabel ('mV');
%     xlabel ('Time (sec)');    
%     legend ('Low-pass filter, Power', 'Putative Onset', 'Detected (final) onsets', 'Potential onset(s)')
%     
%     exportToPPTX('addslide'); %Draw seizure figure on new powerpoint slide
%     exportToPPTX('addpicture',figHandle);      
%     close(figHandle)
    
    %Plot offset detection
    figHandle = figure;
    set(gcf,'NumberTitle','off', 'color', 'w'); %don't show the figure number
    set(gcf,'Name', sprintf ('SLE offset #%d', i)); %select the name you want
    set(gcf, 'Position', get(0, 'Screensize'));   
    
    %Plot filtered LFP signal
    subplot (3,1,1)
    plot(t(offsetContext),LFP_filtered(offsetContext))
    hold on
    plot(t(offsetSLE), LFP_filtered(offsetSLE), 'x', 'color', 'red', 'MarkerSize', 12)  %initial putative (rough) detection
    plot(SLEoffset_final(i,1), LFP_filtered(offsetContext(offset_loc)), 'o', 'color', 'black', 'MarkerSize', 14)   %Detected offset point 
    plot(t(offsetContext(offset_loc)), LFP_filtered(offsetContext(offset_loc)), '*', 'color', 'green', 'MarkerSize', 14)    %All detected potential offsets    
    %Labels
    title (sprintf('Event offset #%d, LFP Bandpass Filtered (1-100 Hz)', i));
    ylabel ('mV');
    xlabel ('Time (sec)');
    
    %Plot of the Power of the derivative signal
    subplot (3,1,2)
    plot(t(offsetContext), vectorOffsetContextCentered)
    hold on
    plot(t(offsetSLE), powerFeatureLowPassFiltered2(offsetSLE)-center, 'x', 'color', 'red', 'MarkerSize', 12)     %initial (rough) detection
    plot(SLEoffset_final(i,1), powerFeatureLowPassFiltered2(offsetContext(offset_loc))-center, 'o', 'color', 'black', 'MarkerSize', 14)    %Detected offset point 
    plot(t(offsetContext(offset_loc)), powerFeatureLowPassFiltered2(offsetContext(offset_loc))-center, '*', 'color', 'green', 'MarkerSize', 14)    %Final (Refined) detection
    %Plot dashed lines where the threshold for offset is
    xL = get(gca, 'XLim');
    plot(xL, [meanOffsetBaseline/2 meanOffsetBaseline/2], '--')
    %Labels
    title (sprintf('Power of derivative signal, Low Pass Filtered (2 Hz): %.2f', SLEoffset_final(i,1)));
    ylabel ('mV');
    xlabel ('Time (sec)');
    legend ('Low-pass filtered, Power of derivative signal', 'Putative Offset', 'detected offset', 'Final Offset', 'Baseline mean/2')       
    
    %Plot of the Power of the Absolute values signal
    subplot (3,1,3)
    plot(t(offsetContext), powerFeatureLowPassFilteredAbs2(offsetContext))
    hold on
    plot(t(offsetSLE), powerFeatureLowPassFilteredAbs2(offsetSLE), 'x', 'color', 'red', 'MarkerSize', 12)     %initial (rough) detection
    plot(SLEoffset_final_Abs(i,1), powerFeatureLowPassFilteredAbs2(offsetContext(offset_loc_Abs)), 'o', 'color', 'black', 'MarkerSize', 14)    %Detected offset point 
    plot(t(offsetContext(offset_loc_Abs)), powerFeatureLowPassFilteredAbs2(offsetContext(offset_loc_Abs)), '*', 'color', 'green', 'MarkerSize', 14)    %Final (Refined) detection
    %Plot dashed lines where the threshold for offset is
    xL = get(gca, 'XLim');
    plot(xL, [meanOffsetAbsBaseline/2 meanOffsetAbsBaseline/2], '--')
    %Labels
    title (sprintf('Power of Absolute signal, Low Pass Filtered (2 Hz): %.2f',SLEoffset_final_Abs(i,1)));
    ylabel ('mV');
    xlabel ('Time (sec)');
    legend ('Low-pass filtered, Power of Absolute signal', 'Putative Offset', 'detected offset', 'Final Offset', 'Baseline mean/2')
    
    exportToPPTX('addslide'); %Draw seizure figure on new powerpoint slide
    exportToPPTX('addpicture',figHandle);      
    close(figHandle)
    end    
   
end

if troubleshooting         
    % save and close the .PPTX
    exportToPPTX('saveandclose','troubleshooting'); 
end

%% Store output - using Abs signal to determine the offset 
%use SLEoffset_final_Abs, as the final offset point
SLEoffset_final = SLEoffset_final_Abs;  %remove this line in the future if you don't want to use the absolute value

duration_final = SLEoffset_final - SLEonset_final;
SLE_final = [SLEonset_final, SLEoffset_final, duration_final];  %final list of SLEs, need to filter out artifacts
SLE_final((SLE_final(:,2)==-1),:) = [];     %remove all the rows where SLE is -1

%Preallocate
SLE_final(:,20)= 0;

if LED
    %Classify which SLEs were light triggered
    for i=1:size(SLE_final,1) 
        %use the "ismember" function 
        SLE_final(i,8)=ismember (int64(SLE_final(i,1)*frequency), lightTriggeredOnsetZones);
    end
end


%% Light pulse detect algorithm by Taufik A. Valiante
function [P] = pulse_seq(x)
% Return structure of all the pulses in a sequence of arbitrary height

% Arbitrary threshold
x = x(:);
thresh = max(x)/10;

pulses = x >= thresh;
trans = diff(pulses);
up = find(trans == 1)+1;
down = find(trans == 1)+1;

if isempty(up) || isempty(down)
    P = [];
else
    range = [up,down];
    dur = (down-up);
    isi = [down(1:end-1),up(2:end)];

    P = struct_from_list('range', range, 'dur', dur, 'isi', isi);
end

