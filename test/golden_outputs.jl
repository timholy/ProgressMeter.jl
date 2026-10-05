# Generated from ProgressMeter v1.11.0 output; the refactor must reproduce these exactly.
const GOLDEN_OUTPUTS = Dict(
    "progress" => "\rWorking:  30%|████████████▋                             |  ETA: H:MM:SS\e[K\rWorking:  40%|████████████████▊                         |  ETA: H:MM:SS\e[K\rWorking: 100%|██████████████████████████████████████████| Time: H:MM:SS\e[K\n",
    "progress_showspeed" => "\rWorking:  30%|████████▍                   |  ETA: H:MM:SS (SPEED/it)\e[K\rWorking: 100%|████████████████████████████| Time: H:MM:SS (SPEED/it)\e[K\n",
    "progress_glyphs_barlen" => "\rProgress:  30%[======>             ]  ETA: H:MM:SS\e[K\rProgress:  70%[==============>     ]  ETA: H:MM:SS\e[K\rProgress: 100%[====================] Time: H:MM:SS\e[K\n",
    "progress_desc_change" => "\rA  30%|█████████                     |  ETA: H:MM:SS\e[K\rLonger description  50%|██████▌      |  ETA: H:MM:SS\e[K\rLonger description 100%|█████████████| Time: H:MM:SS\e[K\n",
    "progress_nobar_start" => "\rProgress:  40%  ETA: H:MM:SS (SPEED/it)\e[K\rProgress: 100% Time: H:MM:SS (SPEED/it)\e[K\n",
    "progress_max_steps" => "\rProgress:  20%|████████▎                                |  ETA: H:MM:SS\e[K\rProgress: 100%|█████████████████████████████████████████| Time: H:MM:SS\e[K\n",
    "progress_showvalues_offset" => "\n\rProgress:  30%|████████████▎                            |  ETA: H:MM:SS\e[K\r\n     a: 1\e[K\r\n   bbb: x\e[K\r\e[A\r\e[A\r\e[A\n\n\n\r\e[K\e[A\r\e[K\e[A\rProgress: 100%|█████████████████████████████████████████| Time: H:MM:SS\e[K\r\n   a: 2\e[K\r\e[A\r\e[A",
    "progress_cancel" => "\rProgress:  30%|████████████▎                            |  ETA: H:MM:SS\e[K\rAborted before all tasks were completed\e[K\n",
    "progress_color" => "\r\e[31mProgress:  30%|███       |  ETA: H:MM:SS\e[39m\e[K\r\e[33mProgress: 100%|██████████| Time: H:MM:SS\e[39m\e[K\n",
    "thresh" => "\rMinimizing: (thresh = 0.1, value = 0.5)\e[K\rMinimizing: (thresh = 0.1, value = 0.2)\e[K\rMinimizing: Time: H:MM:SS (3 iterations)\e[K\n",
    "thresh_showspeed" => "\rProgress:  (thresh = 0.1, value = 0.5) (SPEED/it)\e[K\rProgress:  Time: H:MM:SS (2 iterations) (SPEED/it)\e[K\n",
    "unknown" => "\rReading: 1    Time: H:MM:SS\e[K\rReading: 2    Time: H:MM:SS\e[K\rReading: 2    Time: H:MM:SS\e[K\n",
    "unknown_spinner_speed" => "\r◐ Spinning:    Time: H:MM:SS (SPEED/it)\e[K\rb Spinning:    Time: H:MM:SS (SPEED/it)\e[K\r✓ Spinning:    Time: H:MM:SS (SPEED/it)\e[K\n",
)
